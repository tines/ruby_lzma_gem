/* cpp_bridge.cpp - C++ bridge implementation
 * This file implements the C++ bridge that interfaces with the 7-Zip SDK
 */

#include "cpp_bridge.hpp"
#include "archive_callbacks.hpp"
#include <cstring>
#include <cstdio>
#include <stdexcept>
#include <sys/stat.h>

// C++ API includes
#include "lzma_sdk/CPP/7zip/Archive/IArchive.h"
#include "lzma_sdk/CPP/7zip/Common/FileStreams.h"
#include "lzma_sdk/CPP/7zip/Common/StreamObjects.h"
#include "lzma_sdk/CPP/Common/MyCom.h"
#include "lzma_sdk/CPP/Common/StringConvert.h"

// 7z handler creation function (from ArchiveExports.cpp)
STDAPI CreateArchiver(const GUID *clsid, const GUID *iid, void **outObject);

// Helper function to initialize a format GUID based on format constant
// GUID format: {23170F69-40C1-278A-1000-0001100X0000}
// The byte at Data4[5] identifies the format:
//   0x07 = 7z, 0x01 = Zip, 0xEE = Tar
static void InitFormatGUID(GUID* guid, int format) {
    memset(guid, 0, sizeof(GUID));
    guid->Data1 = 0x23170F69;
    guid->Data2 = 0x40C1;
    guid->Data3 = 0x278A;
    guid->Data4[0] = 0x10;
    guid->Data4[1] = 0x00;
    guid->Data4[2] = 0x00;
    guid->Data4[3] = 0x01;
    guid->Data4[4] = 0x10;
    guid->Data4[6] = 0x00;
    guid->Data4[7] = 0x00;

    // Map our format constants to SDK format IDs
    switch (format) {
        case SZ_FORMAT_ZIP:
            guid->Data4[5] = 0x01;  // kId_Zip
            break;
        case SZ_FORMAT_TAR:
            guid->Data4[5] = 0xEE;  // kId_Tar
            break;
        case SZ_FORMAT_7Z:
        default:
            guid->Data4[5] = 0x07;  // kId_7z
            break;
    }
}

// Memory-based input stream for reading archives from memory buffers
// This allows opening archives from StringIO or raw byte arrays
class CMemoryInStream Z7_final:
  public IInStream,
  public IStreamGetSize,
  public CMyUnknownImp
{
  Z7_COM_UNKNOWN_IMP_3(
      IInStream,
      ISequentialInStream,
      IStreamGetSize)

  Z7_IFACE_COM7_IMP(ISequentialInStream)
  Z7_IFACE_COM7_IMP(IInStream)
  Z7_IFACE_COM7_IMP(IStreamGetSize)

private:
  const Byte *_data;
  UInt64 _size;
  UInt64 _pos;

public:
  CMemoryInStream(const Byte *data, UInt64 size) : _data(data), _size(size), _pos(0) {}

  bool IsOpen() const { return _data != NULL; }
  UInt64 GetSize() const { return _size; }
  UInt64 GetPos() const { return _pos; }
};

// Implementation of CMemoryInStream methods
Z7_COM7F_IMF(CMemoryInStream::Read(void *data, UInt32 size, UInt32 *processedSize))
{
  if (processedSize)
    *processedSize = 0;
  if (!_data)
    return E_FAIL;

  UInt64 remain = _size - _pos;
  if (size > remain)
    size = (UInt32)remain;

  if (size > 0)
  {
    memcpy(data, _data + _pos, size);
    _pos += size;
  }

  if (processedSize)
    *processedSize = size;
  return S_OK;
}

Z7_COM7F_IMF(CMemoryInStream::Seek(Int64 offset, UInt32 seekOrigin, UInt64 *newPosition))
{
  if (!_data)
    return E_FAIL;

  UInt64 newPos = _pos;
  switch (seekOrigin)
  {
    case STREAM_SEEK_SET:
      newPos = offset;
      break;
    case STREAM_SEEK_CUR:
      newPos = _pos + offset;
      break;
    case STREAM_SEEK_END:
      newPos = _size + offset;
      break;
    default:
      return STG_E_INVALIDFUNCTION;
  }

  if (newPos > _size)
    return HRESULT_WIN32_ERROR_NEGATIVE_SEEK;

  _pos = newPos;
  if (newPosition)
    *newPosition = _pos;
  return S_OK;
}

Z7_COM7F_IMF(CMemoryInStream::GetSize(UInt64 *size))
{
  if (!_data)
    return E_FAIL;
  *size = _size;
  return S_OK;
}

namespace LzmaSdkWrapper {

/* ========== ArchiveReader Implementation ========== */

class ArchiveReader::Impl {
public:
    bool isOpen;

    Impl() : isOpen(false) {}
};

ArchiveReader::ArchiveReader()
    : pImpl(new Impl())  // Use new directly for C++11 compatibility
    , archiveFormat(SZ_FORMAT_7Z)
    , progressCallback(nullptr)
    , progressUserData(nullptr)
    , isMemoryBased(false)
    , memoryArchive(nullptr)
    , fileArchive(nullptr)
    , fileStream(nullptr) {
}

ArchiveReader::~ArchiveReader() {
    close();
}

int ArchiveReader::open(const char* path, int format) {
    try {
        // Store archive path and format for later use
        archivePath = path;
        archiveFormat = format;

        // Initialize format GUID based on the requested format
        GUID CLSID_Format;
        InitFormatGUID(&CLSID_Format, format);

        // Create archive handler for the requested format
        CMyComPtr<IInArchive> archive;
        HRESULT hr = CreateArchiver(&CLSID_Format, &IID_IInArchive, (void**)&archive);
        if (hr != S_OK || !archive) {
            errorMessage = "Failed to create archive handler for format";
            return SZW_ERROR_FAIL;
        }

        // Open file stream
        CInFileStream *fileSpec = new CInFileStream;
        CMyComPtr<IInStream> file = fileSpec;

        FString archivePathFS = us2fs(GetUnicodeString(path));
        if (!fileSpec->Open(archivePathFS)) {
            errorMessage = "Failed to open archive file";
            return SZW_ERROR_OPEN_FAILED;
        }

        // Create open callback with password
        CArchiveOpenCallback *openCallbackSpec = new CArchiveOpenCallback;
        CMyComPtr<IArchiveOpenCallback> openCallback(openCallbackSpec);
        if (!password.empty()) {
            openCallbackSpec->SetPassword(password.c_str());
        }

        // Open archive
        const UInt64 scanSize = 1 << 23;
        hr = archive->Open(file, &scanSize, openCallback);
        if (hr != S_OK) {
            char errBuf[256];
            snprintf(errBuf, sizeof(errBuf), "Failed to open archive (HRESULT: 0x%08X)", (unsigned int)hr);
            errorMessage = errBuf;
            return SZW_ERROR_OPEN_FAILED;
        }

        // Cache the archive and stream for extraction
        archive->AddRef();
        fileArchive = archive.Detach();

        file->AddRef();
        fileStream = file.Detach();

        pImpl->isOpen = true;

        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        return SZW_ERROR_FAIL;
    }
}

int ArchiveReader::openFromMemory(const uint8_t* data, size_t size, int format) {
    try {
        if (!data || size == 0) {
            errorMessage = "Invalid memory buffer";
            return SZW_ERROR_INVALIDARG;
        }

        // Store the format for later use
        archiveFormat = format;

        // Copy buffer data (we need to own it for the lifetime of the reader)
        memoryBuffer.assign(data, data + size);

        // Initialize format GUID based on the requested format
        GUID CLSID_Format;
        InitFormatGUID(&CLSID_Format, format);

        // Create archive handler for the requested format
        CMyComPtr<IInArchive> archive;
        HRESULT hr = CreateArchiver(&CLSID_Format, &IID_IInArchive, (void**)&archive);
        if (hr != S_OK || !archive) {
            errorMessage = "Failed to create archive handler for format";
            return SZW_ERROR_FAIL;
        }

        // Create memory stream
        CMemoryInStream *streamSpec = new CMemoryInStream(memoryBuffer.data(), memoryBuffer.size());
        CMyComPtr<IInStream> stream = streamSpec;

        // Create open callback with password
        CArchiveOpenCallback *openCallbackSpec = new CArchiveOpenCallback;
        CMyComPtr<IArchiveOpenCallback> openCallback(openCallbackSpec);

        if (!password.empty()) {
            openCallbackSpec->SetPassword(password.c_str());
        }

        // Open archive
        const UInt64 scanSize = 1 << 23;
        hr = archive->Open(stream, &scanSize, openCallback);
        if (hr != S_OK) {
            char errBuf[256];
            snprintf(errBuf, sizeof(errBuf), "Failed to open archive from memory (HRESULT: 0x%08X)", (unsigned int)hr);
            errorMessage = errBuf;
            return SZW_ERROR_OPEN_FAILED;
        }

        // Store the archive interface (need to AddRef to keep it alive)
        archive->AddRef();
        memoryArchive = archive.Detach();

        isMemoryBased = true;
        pImpl->isOpen = true;

        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        return SZW_ERROR_FAIL;
    }
}

void ArchiveReader::close() {
    if (pImpl->isOpen) {
        // Release file-based archive
        if (fileArchive) {
            static_cast<IInArchive*>(fileArchive)->Release();
            fileArchive = nullptr;
        }
        if (fileStream) {
            static_cast<IInStream*>(fileStream)->Release();
            fileStream = nullptr;
        }

        // Release memory-based archive
        if (isMemoryBased) {
            if (memoryArchive) {
                static_cast<IInArchive*>(memoryArchive)->Release();
                memoryArchive = nullptr;
            }
            memoryBuffer.clear();
            isMemoryBased = false;
        }

        pImpl->isOpen = false;
    }
}

uint32_t ArchiveReader::getEntryCount() {
    if (!pImpl->isOpen) {
        return 0;
    }

    IInArchive* archive = nullptr;
    if (isMemoryBased) {
        archive = static_cast<IInArchive*>(memoryArchive);
    } else {
        archive = static_cast<IInArchive*>(fileArchive);
    }

    if (!archive) {
        return 0;
    }

    UInt32 numItems = 0;
    archive->GetNumberOfItems(&numItems);
    return numItems;
}

int ArchiveReader::getEntryInfo(uint32_t index, SzEntryInfo* info) {
    if (!pImpl->isOpen || !info) {
        return SZW_ERROR_INVALIDARG;
    }

    IInArchive* archive = nullptr;
    if (isMemoryBased) {
        archive = static_cast<IInArchive*>(memoryArchive);
    } else {
        archive = static_cast<IInArchive*>(fileArchive);
    }

    if (!archive) {
        errorMessage = "No archive open";
        return SZW_ERROR_FAIL;
    }

    UInt32 numItems = 0;
    archive->GetNumberOfItems(&numItems);
    if (index >= numItems) {
        return SZW_ERROR_INVALIDARG;
    }

    try {
        // Get file path
        NWindows::NCOM::CPropVariant prop;

        HRESULT hr = archive->GetProperty(index, kpidPath, &prop);
        if (hr == S_OK && prop.vt == VT_BSTR) {
            // Convert BSTR (UTF-16) to UTF-8
            const wchar_t* wstr = prop.bstrVal;
            size_t maxLen = sizeof(info->name) - 1;
            for (size_t i = 0; i < maxLen && wstr[i] != 0; i++) {
                if (wstr[i] < 128) {
                    info->name[i] = (char)wstr[i];
                } else {
                    info->name[i] = '?';
                }
                info->name[i + 1] = '\0';
            }
        } else {
            info->name[0] = '\0';
        }

        // Get uncompressed size
        hr = archive->GetProperty(index, kpidSize, &prop);
        if (hr == S_OK && prop.vt == VT_UI8) {
            info->size = prop.uhVal.QuadPart;
        } else {
            info->size = 0;
        }

        // Get compressed size
        hr = archive->GetProperty(index, kpidPackSize, &prop);
        if (hr == S_OK && prop.vt == VT_UI8) {
            info->compressed_size = prop.uhVal.QuadPart;
        } else {
            info->compressed_size = 0;
        }

        // Get directory flag
        hr = archive->GetProperty(index, kpidIsDir, &prop);
        if (hr == S_OK && prop.vt == VT_BOOL) {
            info->is_directory = (prop.boolVal != VARIANT_FALSE);
        } else {
            info->is_directory = false;
        }

        // Get CRC
        hr = archive->GetProperty(index, kpidCRC, &prop);
        if (hr == S_OK && prop.vt == VT_UI4) {
            info->crc = prop.ulVal;
        } else {
            info->crc = 0;
        }

        // Get modified time
        hr = archive->GetProperty(index, kpidMTime, &prop);
        if (hr == S_OK && prop.vt == VT_FILETIME) {
            // Convert FILETIME to Unix timestamp
            UInt64 winTime = ((UInt64)prop.filetime.dwHighDateTime << 32) | prop.filetime.dwLowDateTime;
            if (winTime > 116444736000000000ULL) {
                info->modified_time = (winTime - 116444736000000000ULL) / 10000000ULL;
            } else {
                info->modified_time = 0;
            }
        } else {
            info->modified_time = 0;
        }

        // Get attributes
        hr = archive->GetProperty(index, kpidAttrib, &prop);
        if (hr == S_OK && prop.vt == VT_UI4) {
            info->attributes = prop.ulVal;
        } else {
            info->attributes = 0;
        }

        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        return SZW_ERROR_FAIL;
    }
}

// Helper function for C++ API extraction to file
int ArchiveReader::extractToFile_CPP(uint32_t index, const char* output_path) {
    try {
        CMyComPtr<IInArchive> archive;

        // Get the cached archive (file-based or memory-based)
        if (fileArchive) {
            archive = static_cast<IInArchive*>(fileArchive);
            archive->AddRef();
        } else if (isMemoryBased && memoryArchive) {
            archive = static_cast<IInArchive*>(memoryArchive);
            archive->AddRef();
        } else {
            errorMessage = "No archive open";
            return SZW_ERROR_FAIL;
        }

        // Create extract callback with password
        CArchiveExtractCallback *extractCallbackSpec = new CArchiveExtractCallback;
        CMyComPtr<IArchiveExtractCallback> extractCallback(extractCallbackSpec);
        extractCallbackSpec->Init(archive, index, output_path);

        if (!password.empty()) {
            extractCallbackSpec->SetPassword(password.c_str());
        }

        // Extract the single file
        const UInt32 indices[1] = { index };
        HRESULT hr = archive->Extract(indices, 1, 0, extractCallback);

        if (hr != S_OK) {
            char errBuf[256];
            snprintf(errBuf, sizeof(errBuf), "Extraction failed (HRESULT: 0x%08X)", (unsigned int)hr);
            errorMessage = errBuf;
            return SZW_ERROR_EXTRACT_FAILED;
        }

        UInt64 numErrors = extractCallbackSpec->GetNumErrors();
        if (numErrors > 0) {
            char errBuf[256];
            snprintf(errBuf, sizeof(errBuf), "Extraction completed with %llu errors",
                    (unsigned long long)numErrors);
            errorMessage = errBuf;
            return SZW_ERROR_EXTRACT_FAILED;
        }

        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        return SZW_ERROR_FAIL;
    }
}

int ArchiveReader::extractToFile(uint32_t index, const char* output_path) {
    if (!pImpl->isOpen) {
        errorMessage = "Archive not open";
        return SZW_ERROR_FAIL;
    }

    if (!output_path) {
        errorMessage = "Output path is null";
        return SZW_ERROR_INVALIDARG;
    }

    return extractToFile_CPP(index, output_path);
}

int ArchiveReader::extractToMemory(uint32_t index, uint8_t** buffer, size_t* size) {
    if (!pImpl->isOpen) {
        errorMessage = "Archive not open";
        return SZW_ERROR_FAIL;
    }

    try {
        CMyComPtr<IInArchive> archive;

        // Get the cached archive (file-based or memory-based)
        if (fileArchive) {
            archive = static_cast<IInArchive*>(fileArchive);
            archive->AddRef();
        } else if (isMemoryBased && memoryArchive) {
            archive = static_cast<IInArchive*>(memoryArchive);
            archive->AddRef();
        } else {
            errorMessage = "No archive open";
            return SZW_ERROR_FAIL;
        }

        // Create memory output stream
        CDynBufSeqOutStream *outStreamSpec = new CDynBufSeqOutStream;
        CMyComPtr<ISequentialOutStream> outStream(outStreamSpec);
        outStreamSpec->Init();

        // Create extract callback
        CArchiveExtractCallbackMemory *extractCallbackSpec = new CArchiveExtractCallbackMemory;
        CMyComPtr<IArchiveExtractCallback> extractCallback(extractCallbackSpec);
        extractCallbackSpec->Init(archive, index, outStream);

        if (!password.empty()) {
            extractCallbackSpec->SetPassword(password.c_str());
        }

        // Extract the single file
        const UInt32 indices[1] = { index };
        HRESULT hr = archive->Extract(indices, 1, 0, extractCallback);

        if (hr != S_OK) {
            errorMessage = "Extraction failed";
            return SZW_ERROR_EXTRACT_FAILED;
        }

        if (extractCallbackSpec->GetNumErrors() > 0) {
            errorMessage = "Extraction completed with errors";
            return SZW_ERROR_EXTRACT_FAILED;
        }

        // Get the extracted data
        size_t dataSize = outStreamSpec->GetSize();
        const Byte *data = outStreamSpec->GetBuffer();

        // Allocate buffer and copy data (caller must free this)
        *buffer = (uint8_t*)malloc(dataSize);
        if (!*buffer) {
            errorMessage = "Out of memory";
            return SZW_ERROR_OUTOFMEMORY;
        }

        memcpy(*buffer, data, dataSize);
        *size = dataSize;

        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        return SZW_ERROR_FAIL;
    }
}

int ArchiveReader::verify() {
    if (!pImpl->isOpen) {
        errorMessage = "Archive not open";
        return SZW_ERROR_FAIL;
    }

    try {
        // Initialize format GUID using stored format
        GUID CLSID_Format;
        InitFormatGUID(&CLSID_Format, archiveFormat);

        // Create archive handler for the stored format
        CMyComPtr<IInArchive> archive;
        HRESULT hr = CreateArchiver(&CLSID_Format, &IID_IInArchive, (void**)&archive);
        if (hr != S_OK || !archive) {
            errorMessage = "Failed to create archive handler";
            return SZW_ERROR_FAIL;
        }

        // Open stream (file or memory)
        CMyComPtr<IInStream> stream;

        if (isMemoryBased) {
            // Create memory stream from stored buffer
            CMemoryInStream *memStreamSpec = new CMemoryInStream(memoryBuffer.data(), memoryBuffer.size());
            stream = memStreamSpec;
        } else {
            // Open file stream
            CInFileStream *fileSpec = new CInFileStream;
            stream = fileSpec;

            FString archivePathFS = us2fs(GetUnicodeString(archivePath.c_str()));
            if (!fileSpec->Open(archivePathFS)) {
                errorMessage = "Failed to open archive file";
                return SZW_ERROR_OPEN_FAILED;
            }
        }

        // Create open callback with password
        CArchiveOpenCallback *openCallbackSpec = new CArchiveOpenCallback;
        CMyComPtr<IArchiveOpenCallback> openCallback(openCallbackSpec);

        if (!password.empty()) {
            openCallbackSpec->SetPassword(password.c_str());
        }

        // Open archive
        const UInt64 scanSize = 1 << 23;
        hr = archive->Open(stream, &scanSize, openCallback);
        if (hr != S_OK) {
            errorMessage = "Failed to open archive or incorrect password";
            return SZW_ERROR_PASSWORD_INCORRECT;
        }

        // Create verify callback
        CArchiveExtractCallbackVerify *extractCallbackSpec = new CArchiveExtractCallbackVerify;
        CMyComPtr<IArchiveExtractCallback> extractCallback(extractCallbackSpec);
        extractCallbackSpec->Init(archive);

        if (!password.empty()) {
            extractCallbackSpec->SetPassword(password.c_str());
        }

        // Test all files (use kTest mode)
        hr = archive->Extract(NULL, (UInt32)(Int32)(-1), 1, extractCallback);

        if (hr != S_OK) {
            errorMessage = "Verification failed";
            return SZW_ERROR_CORRUPT_ARCHIVE;
        }

        if (extractCallbackSpec->GetNumErrors() > 0) {
            errorMessage = "Verification found errors";
            return SZW_ERROR_CORRUPT_ARCHIVE;
        }

        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        return SZW_ERROR_FAIL;
    }
}

int ArchiveReader::setPassword(const char* pwd) {
    if (pwd) {
        password = pwd;
    } else {
        password.clear();
    }
    return SZW_OK;
}

int ArchiveReader::setProgressCallback(SzProgressCallback callback, void* user_data) {
    progressCallback = callback;
    progressUserData = user_data;
    return SZW_OK;
}

const char* ArchiveReader::getErrorMessage() {
    return errorMessage.c_str();
}

/* ========== ArchiveWriter Implementation ========== */

class ArchiveWriter::Impl {
public:
    std::string archivePath;
    int format;
    std::vector<CArchiveItem> items;
    bool isOpen;

    Impl() : format(SZ_FORMAT_7Z), isOpen(false) {}
};

ArchiveWriter::ArchiveWriter()
    : pImpl(new Impl())  // Use new directly for C++11 compatibility
    , progressCallback(nullptr)
    , progressUserData(nullptr) {
    memset(&options, 0, sizeof(options));
    options.method = SZ_METHOD_LZMA2;
    options.level = SZ_LEVEL_NORMAL;
}

ArchiveWriter::~ArchiveWriter() {
    // Note: finalize() should be called explicitly before destruction
    // We don't call it here because errors can't be propagated from destructors
}

int ArchiveWriter::create(const char* path, int format, const SzCompressionOptions* opts) {
    try {
        pImpl->archivePath = path;
        pImpl->format = format;
        pImpl->items.clear();

        if (opts) {
            options = *opts;
        }

        pImpl->isOpen = true;
        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        return SZW_ERROR_FAIL;
    }
}

int ArchiveWriter::finalize() {
    if (!pImpl->isOpen) {
        return SZW_OK;  // Already finalized
    }

    try {
        // Initialize format GUID using the stored format
        GUID CLSID_Format;
        InitFormatGUID(&CLSID_Format, pImpl->format);

        // Create output archive handler for the requested format
        CMyComPtr<IOutArchive> outArchive;
        HRESULT hr = CreateArchiver(&CLSID_Format, &IID_IOutArchive, (void**)&outArchive);
        if (hr != S_OK || !outArchive) {
            errorMessage = "Failed to create output archive handler";
            pImpl->isOpen = false;
            return SZW_ERROR_FAIL;
        }

        // Set compression properties if needed
        if (options.level != SZ_LEVEL_NORMAL || options.method != SZ_METHOD_LZMA2 || !options.solid) {
            CMyComPtr<ISetProperties> setProperties;
            outArchive->QueryInterface(IID_ISetProperties, (void**)&setProperties);
            if (setProperties) {
                const wchar_t *names[3];
                NWindows::NCOM::CPropVariant values[3];
                unsigned numProps = 0;

                // Compression level
                names[numProps] = L"x";
                values[numProps] = (UInt32)options.level;
                numProps++;

                // Solid mode
                names[numProps] = L"s";
                values[numProps] = options.solid;
                numProps++;

                // Method
                if (options.method == SZ_METHOD_LZMA) {
                    names[numProps] = L"m";
                    values[numProps] = L"lzma";
                    numProps++;
                } else if (options.method == SZ_METHOD_PPMD) {
                    names[numProps] = L"m";
                    values[numProps] = L"ppmd";
                    numProps++;
                }

                setProperties->SetProperties(names, values, numProps);
            }
        }

        // Create output file stream
        COutFileStream *outFileStreamSpec = new COutFileStream;
        CMyComPtr<IOutStream> outFileStream = outFileStreamSpec;

        FString archivePathFS = us2fs(GetUnicodeString(pImpl->archivePath.c_str()));
        if (!outFileStreamSpec->Create_NEW(archivePathFS)) {
            errorMessage = "Failed to create output archive file";
            pImpl->isOpen = false;
            return SZW_ERROR_WRITE_FAILED;
        }

        // Create update callback
        CArchiveUpdateCallback *updateCallbackSpec = new CArchiveUpdateCallback;
        CMyComPtr<IArchiveUpdateCallback2> updateCallback(updateCallbackSpec);
        updateCallbackSpec->Init(&pImpl->items);

        if (!password.empty()) {
            updateCallbackSpec->SetPassword(password.c_str());
        }

        // Perform the update (create archive)
        hr = outArchive->UpdateItems(outFileStream,
                                     static_cast<UInt32>(pImpl->items.size()),
                                     updateCallback);

        pImpl->isOpen = false;

        if (hr != S_OK) {
            char errBuf[256];
            snprintf(errBuf, sizeof(errBuf), "Failed to create archive (HRESULT: 0x%08X)", (unsigned int)hr);
            errorMessage = errBuf;
            return SZW_ERROR_COMPRESS_FAILED;
        }

        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        pImpl->isOpen = false;
        return SZW_ERROR_FAIL;
    }
}

int ArchiveWriter::addFile(const char* src_path, const char* archive_path) {
    if (!pImpl->isOpen) {
        errorMessage = "Archive not open";
        return SZW_ERROR_FAIL;
    }

    try {
        FString fullPath = us2fs(GetUnicodeString(src_path));

        // Check if file exists using standard C API
        struct stat st;
        if (stat(src_path, &st) != 0) {
            errorMessage = "File not found";
            return SZW_ERROR_OPEN_FAILED;
        }

        if (S_ISDIR(st.st_mode)) {
            errorMessage = "Path is a directory, use addDirectory";
            return SZW_ERROR_INVALIDARG;
        }

        CArchiveItem item;
        item.Path = GetUnicodeString(archive_path);
        item.FullPath = fullPath;
        item.Size = st.st_size;
        item.IsDir = false;
        item.IsFromMemory = false;

        pImpl->items.push_back(item);
        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        return SZW_ERROR_FAIL;
    }
}

int ArchiveWriter::addDirectory(const char* src_path, const char* archive_path) {
    if (!pImpl->isOpen) {
        errorMessage = "Archive not open";
        return SZW_ERROR_FAIL;
    }

    try {
        FString basePath = us2fs(GetUnicodeString(src_path));
        UString archiveBase = GetUnicodeString(archive_path);

        // Check if directory exists using standard C API
        struct stat st;
        if (stat(src_path, &st) != 0) {
            errorMessage = "Directory not found";
            return SZW_ERROR_OPEN_FAILED;
        }

        if (!S_ISDIR(st.st_mode)) {
            errorMessage = "Path is not a directory";
            return SZW_ERROR_INVALIDARG;
        }

        // Add the directory entry itself
        CArchiveItem dirItem;
        dirItem.Path = archiveBase;
        dirItem.FullPath = basePath;
        dirItem.Size = 0;
        dirItem.IsDir = true;
        dirItem.IsFromMemory = false;
        pImpl->items.push_back(dirItem);

        // Note: Recursive directory enumeration would require additional
        // platform-specific code. For now, just add the directory entry.
        // Files should be added individually using addFile.

        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        return SZW_ERROR_FAIL;
    }
}

int ArchiveWriter::addData(const uint8_t* data, size_t size, const char* archive_path) {
    if (!pImpl->isOpen) {
        errorMessage = "Archive not open";
        return SZW_ERROR_FAIL;
    }

    try {
        CArchiveItem item;
        item.Path = GetUnicodeString(archive_path);
        item.Size = size;
        item.IsDir = false;
        item.IsFromMemory = true;
        item.Data.assign(data, data + size);

        pImpl->items.push_back(item);
        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        return SZW_ERROR_FAIL;
    }
}

int ArchiveWriter::mkdir(const char* archive_path) {
    if (!pImpl->isOpen) {
        errorMessage = "Archive not open";
        return SZW_ERROR_FAIL;
    }

    try {
        CArchiveItem item;
        item.Path = GetUnicodeString(archive_path);
        item.Size = 0;
        item.IsDir = true;
        item.IsFromMemory = false;

        pImpl->items.push_back(item);
        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        return SZW_ERROR_FAIL;
    }
}

int ArchiveWriter::setPassword(const char* pwd) {
    if (pwd) {
        password = pwd;
    } else {
        password.clear();
    }
    return SZW_OK;
}

int ArchiveWriter::setProgressCallback(SzProgressCallback callback, void* user_data) {
    progressCallback = callback;
    progressUserData = user_data;
    return SZW_OK;
}

const char* ArchiveWriter::getErrorMessage() {
    return errorMessage.c_str();
}

} // namespace LzmaSdkWrapper

/* ========== C Interface Implementations ========== */

extern "C" {

void* cpp_open_archive(const char* path, int format, int* error_code) {
    try {
        auto* reader = new LzmaSdkWrapper::ArchiveReader();
        int result = reader->open(path, format);
        if (result != SZW_OK) {
            delete reader;
            *error_code = result;
            return nullptr;
        }
        *error_code = SZW_OK;
        return static_cast<void*>(reader);
    } catch (...) {
        *error_code = SZW_ERROR_FAIL;
        return nullptr;
    }
}

void* cpp_open_archive_from_memory(const uint8_t* data, size_t size, int format, int* error_code) {
    try {
        auto* reader = new LzmaSdkWrapper::ArchiveReader();
        int result = reader->openFromMemory(data, size, format);
        if (result != SZW_OK) {
            delete reader;
            *error_code = result;
            return nullptr;
        }
        *error_code = SZW_OK;
        return static_cast<void*>(reader);
    } catch (...) {
        *error_code = SZW_ERROR_FAIL;
        return nullptr;
    }
}

int cpp_close_archive(void* handle) {
    try {
        auto* archive = static_cast<LzmaSdkWrapper::ArchiveHandle*>(handle);
        // Call finalize() before destruction to allow writers to complete
        int result = archive->finalize();
        delete archive;
        return result;
    } catch (...) {
        return SZW_ERROR_FAIL;
    }
}

uint32_t cpp_get_entry_count(void* handle) {
    try {
        auto* archive = static_cast<LzmaSdkWrapper::ArchiveHandle*>(handle);
        return archive->getEntryCount();
    } catch (...) {
        return 0;
    }
}

int cpp_get_entry_info(void* handle, uint32_t index, SzEntryInfo* info) {
    try {
        auto* archive = static_cast<LzmaSdkWrapper::ArchiveHandle*>(handle);
        return archive->getEntryInfo(index, info);
    } catch (...) {
        return SZW_ERROR_FAIL;
    }
}

int cpp_extract_to_file(void* handle, uint32_t index, const char* output_path) {
    try {
        auto* archive = static_cast<LzmaSdkWrapper::ArchiveHandle*>(handle);
        return archive->extractToFile(index, output_path);
    } catch (...) {
        return SZW_ERROR_FAIL;
    }
}

int cpp_extract_to_memory(void* handle, uint32_t index, uint8_t** buffer, size_t* size) {
    try {
        auto* archive = static_cast<LzmaSdkWrapper::ArchiveHandle*>(handle);
        return archive->extractToMemory(index, buffer, size);
    } catch (...) {
        return SZW_ERROR_FAIL;
    }
}

int cpp_verify(void* handle) {
    try {
        auto* archive = static_cast<LzmaSdkWrapper::ArchiveHandle*>(handle);
        return archive->verify();
    } catch (...) {
        return SZW_ERROR_FAIL;
    }
}

void* cpp_create_archive(const char* path, int format, const SzCompressionOptions* options) {
    try {
        auto* writer = new LzmaSdkWrapper::ArchiveWriter();
        int result = writer->create(path, format, options);
        if (result != SZW_OK) {
            delete writer;
            return nullptr;
        }
        return static_cast<void*>(writer);
    } catch (...) {
        return nullptr;
    }
}

int cpp_add_file(void* handle, const char* src_path, const char* archive_path) {
    try {
        auto* writer = static_cast<LzmaSdkWrapper::ArchiveWriter*>(handle);
        return writer->addFile(src_path, archive_path);
    } catch (...) {
        return SZW_ERROR_FAIL;
    }
}

int cpp_add_directory(void* handle, const char* src_path, const char* archive_path) {
    try {
        auto* writer = static_cast<LzmaSdkWrapper::ArchiveWriter*>(handle);
        return writer->addDirectory(src_path, archive_path);
    } catch (...) {
        return SZW_ERROR_FAIL;
    }
}

int cpp_add_data(void* handle, const uint8_t* data, size_t size, const char* archive_path) {
    try {
        auto* writer = static_cast<LzmaSdkWrapper::ArchiveWriter*>(handle);
        return writer->addData(data, size, archive_path);
    } catch (...) {
        return SZW_ERROR_FAIL;
    }
}

int cpp_mkdir(void* handle, const char* archive_path) {
    try {
        auto* writer = static_cast<LzmaSdkWrapper::ArchiveWriter*>(handle);
        return writer->mkdir(archive_path);
    } catch (...) {
        return SZW_ERROR_FAIL;
    }
}

int cpp_set_password(void* handle, const char* password) {
    try {
        auto* archive = static_cast<LzmaSdkWrapper::ArchiveHandle*>(handle);
        return archive->setPassword(password);
    } catch (...) {
        return SZW_ERROR_FAIL;
    }
}

int cpp_set_progress_callback(void* handle, SzProgressCallback callback, void* user_data) {
    try {
        auto* archive = static_cast<LzmaSdkWrapper::ArchiveHandle*>(handle);
        return archive->setProgressCallback(callback, user_data);
    } catch (...) {
        return SZW_ERROR_FAIL;
    }
}

const char* cpp_get_error_message(void* handle) {
    try {
        auto* archive = static_cast<LzmaSdkWrapper::ArchiveHandle*>(handle);
        return archive->getErrorMessage();
    } catch (...) {
        return "Unknown error";
    }
}

} // extern "C"
