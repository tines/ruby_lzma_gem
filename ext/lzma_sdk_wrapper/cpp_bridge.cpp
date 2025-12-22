/* cpp_bridge.cpp - C++ bridge implementation
 * This file implements the C++ bridge that interfaces with the 7-Zip SDK
 */

#include "cpp_bridge.hpp"
#include "archive_callbacks.hpp"
#include <cstring>
#include <cstdio>
#include <stdexcept>
#include <sys/stat.h>

// C++ API includes for password support
#include "lzma_sdk/CPP/7zip/Archive/IArchive.h"
#include "lzma_sdk/CPP/7zip/Common/FileStreams.h"
#include "lzma_sdk/CPP/7zip/Common/StreamObjects.h"
#include "lzma_sdk/CPP/Common/MyCom.h"
#include "lzma_sdk/CPP/Common/StringConvert.h"

// 7z handler creation function (from ArchiveExports.cpp)
STDAPI CreateArchiver(const GUID *clsid, const GUID *iid, void **outObject);

// Helper function to initialize 7z format GUID
// GUID format: {23170F69-40C1-278A-1000-000110070000}
// The last byte before the two zeros (0x07) identifies the 7z format
static void Init7zFormatGUID(GUID* guid) {
    memset(guid, 0, sizeof(GUID));
    guid->Data1 = 0x23170F69;
    guid->Data2 = 0x40C1;
    guid->Data3 = 0x278A;
    guid->Data4[0] = 0x10;
    guid->Data4[1] = 0x00;
    guid->Data4[2] = 0x00;
    guid->Data4[3] = 0x01;
    guid->Data4[4] = 0x10;
    guid->Data4[5] = 0x07;  // Format ID: 7z
    guid->Data4[6] = 0x00;
    guid->Data4[7] = 0x00;
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
    CFileInStream archiveStream;
    CLookToRead2 lookStream;
    CSzArEx db;
    ISzAlloc allocImp;
    ISzAlloc allocTempImp;
    bool isOpen;
    UInt16 *tempBuf;
    size_t tempBufSize;

    static const size_t kInputBufSize = (1 << 18); // 256KB buffer

    Impl() : isOpen(false), tempBuf(nullptr), tempBufSize(0) {
        allocImp.Alloc = SzAlloc;
        allocImp.Free = SzFree;
        allocTempImp.Alloc = SzAllocTemp;
        allocTempImp.Free = SzFreeTemp;
        lookStream.buf = nullptr;
    }

    ~Impl() {
        if (tempBuf) {
            ISzAlloc_Free(&allocImp, tempBuf);
        }
        if (lookStream.buf) {
            ISzAlloc_Free(&allocImp, lookStream.buf);
        }
    }
};

ArchiveReader::ArchiveReader()
    : pImpl(new Impl())  // Use new directly for C++11 compatibility
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
        // Store archive path for C++ API use
        archivePath = path;

        // If password is set, use C++ API from the start for better performance
        if (!password.empty()) {

            // Initialize 7z format GUID
            GUID CLSID_Format7z;
            Init7zFormatGUID(&CLSID_Format7z);

            // Create 7z archive handler
            CMyComPtr<IInArchive> archive;
            HRESULT hr = CreateArchiver(&CLSID_Format7z, &IID_IInArchive, (void**)&archive);
            if (hr != S_OK || !archive) {
                errorMessage = "Failed to create 7z handler";
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
            openCallbackSpec->SetPassword(password.c_str());

            // Open archive
            const UInt64 scanSize = 1 << 23;
            hr = archive->Open(file, &scanSize, openCallback);
            if (hr != S_OK) {
                char errBuf[256];
                snprintf(errBuf, sizeof(errBuf), "Failed to open password-protected archive (HRESULT: 0x%08X)", (unsigned int)hr);
                errorMessage = errBuf;
                return SZW_ERROR_OPEN_FAILED;
            }

            // Cache the archive and stream for extraction
            archive->AddRef();
            fileArchive = archive.Detach();

            file->AddRef();
            fileStream = file.Detach();

            // Also initialize the C API db for entry count queries
            // (We'll get entry count from C++ API instead)
            pImpl->isOpen = true;

            return SZW_OK;
        }

        // For unencrypted archives, use fast C API

        if (InFile_Open(&pImpl->archiveStream.file, path)) {
            errorMessage = "Failed to open file";
            return SZW_ERROR_OPEN_FAILED;
        }

        FileInStream_CreateVTable(&pImpl->archiveStream);
        LookToRead2_CreateVTable(&pImpl->lookStream, False);

        // Allocate buffer for LookToRead2
        pImpl->lookStream.buf = (Byte *)ISzAlloc_Alloc(&pImpl->allocImp, pImpl->kInputBufSize);
        if (!pImpl->lookStream.buf) {
            File_Close(&pImpl->archiveStream.file);
            errorMessage = "Failed to allocate read buffer";
            return SZW_ERROR_OUTOFMEMORY;
        }

        pImpl->lookStream.bufSize = pImpl->kInputBufSize;
        pImpl->lookStream.realStream = &pImpl->archiveStream.vt;
        LookToRead2_INIT(&pImpl->lookStream);

        CrcGenerateTable();
        SzArEx_Init(&pImpl->db);

        SRes res = SzArEx_Open(&pImpl->db, &pImpl->lookStream.vt, &pImpl->allocImp, &pImpl->allocTempImp);
        if (res != SZ_OK) {
            File_Close(&pImpl->archiveStream.file);
            errorMessage = "Failed to open archive";
            return SZW_ERROR_OPEN_FAILED;
        }

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

        // Copy buffer data (we need to own it for the lifetime of the reader)
        memoryBuffer.assign(data, data + size);

        // Initialize 7z format GUID
        GUID CLSID_Format7z;
        Init7zFormatGUID(&CLSID_Format7z);

        // Create 7z archive handler
        CMyComPtr<IInArchive> archive;
        HRESULT hr = CreateArchiver(&CLSID_Format7z, &IID_IInArchive, (void**)&archive);
        if (hr != S_OK || !archive) {
            errorMessage = "Failed to create 7z handler";
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
        // Release cached C++ file archive if present
        if (fileArchive) {
            static_cast<IInArchive*>(fileArchive)->Release();
            fileArchive = nullptr;
        }
        if (fileStream) {
            static_cast<IInStream*>(fileStream)->Release();
            fileStream = nullptr;
        }

        if (isMemoryBased) {
            // Release memory-based archive
            if (memoryArchive) {
                static_cast<IInArchive*>(memoryArchive)->Release();
                memoryArchive = nullptr;
            }
            memoryBuffer.clear();
            isMemoryBased = false;
        } else if (!fileArchive) {
            // Release file-based C API archive (only if we didn't use C++ API)
            SzArEx_Free(&pImpl->db, &pImpl->allocImp);
            File_Close(&pImpl->archiveStream.file);
        }
        pImpl->isOpen = false;
    }
}

uint32_t ArchiveReader::getEntryCount() {
    if (!pImpl->isOpen) {
        return 0;
    }

    // Check if using C++ API (memory-based or file-based with password)
    IInArchive* archive = nullptr;
    if (isMemoryBased) {
        archive = static_cast<IInArchive*>(memoryArchive);
    } else if (fileArchive) {
        archive = static_cast<IInArchive*>(fileArchive);
    }

    if (archive) {
        UInt32 numItems = 0;
        archive->GetNumberOfItems(&numItems);
        return numItems;
    }

    // Fall back to C API
    return pImpl->db.NumFiles;
}

int ArchiveReader::getEntryInfo(uint32_t index, SzEntryInfo* info) {
    if (!pImpl->isOpen || !info) {
        return SZW_ERROR_INVALIDARG;
    }

    // Check if using C++ API (memory-based or file-based with password)
    IInArchive* archive = nullptr;
    if (isMemoryBased) {
        archive = static_cast<IInArchive*>(memoryArchive);
    } else if (fileArchive) {
        archive = static_cast<IInArchive*>(fileArchive);
    }

    if (archive) {
        // Handle archives using C++ COM API

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

    // Handle file-based archives using C API
    if (index >= pImpl->db.NumFiles) {
        return SZW_ERROR_INVALIDARG;
    }

    try {
        /* Get filename */
        size_t len = SzArEx_GetFileNameUtf16(&pImpl->db, index, nullptr);
        if (len > pImpl->tempBufSize) {
            ISzAlloc_Free(&pImpl->allocImp, pImpl->tempBuf);
            pImpl->tempBufSize = len;
            pImpl->tempBuf = (UInt16 *)ISzAlloc_Alloc(&pImpl->allocImp, pImpl->tempBufSize * sizeof(UInt16));
            if (!pImpl->tempBuf) {
                pImpl->tempBufSize = 0;
                return SZW_ERROR_OUTOFMEMORY;
            }
        }

        SzArEx_GetFileNameUtf16(&pImpl->db, index, pImpl->tempBuf);

        /* Convert UTF-16 to UTF-8 (simplified) */
        char* namePtr = info->name;
        size_t maxLen = sizeof(info->name) - 1;
        for (size_t i = 0; i < len && i < maxLen; i++) {
            if (pImpl->tempBuf[i] < 128) {
                *namePtr++ = (char)pImpl->tempBuf[i];
            } else {
                *namePtr++ = '?';  /* Simplified: replace non-ASCII with ? */
            }
        }
        *namePtr = '\0';

        /* Fill in other fields from CSzArEx structure */
        info->size = SzArEx_GetFileSize(&pImpl->db, index);
        info->compressed_size = 0;  /* Not easily available in 7z SDK */
        info->is_directory = SzArEx_IsDir(&pImpl->db, index) ? true : false;

        /* Get CRC if available */
        if (SzBitWithVals_Check(&pImpl->db.CRCs, index)) {
            info->crc = pImpl->db.CRCs.Vals[index];
        } else {
            info->crc = 0;
        }

        /* Get modified time if available */
        if (SzBitWithVals_Check(&pImpl->db.MTime, index)) {
            CNtfsFileTime *ft = &pImpl->db.MTime.Vals[index];
            /* Convert Windows FILETIME to Unix timestamp (simplified) */
            UInt64 winTime = ((UInt64)ft->High << 32) | ft->Low;
            /* Windows epoch is 1601-01-01, Unix epoch is 1970-01-01 */
            /* 116444736000000000 is the difference in 100ns intervals */
            if (winTime > 116444736000000000ULL) {
                info->modified_time = (winTime - 116444736000000000ULL) / 10000000ULL;
            } else {
                info->modified_time = 0;
            }
        } else {
            info->modified_time = 0;
        }

        /* Get attributes if available */
        if (SzBitWithVals_Check(&pImpl->db.Attribs, index)) {
            info->attributes = pImpl->db.Attribs.Vals[index];
        } else {
            info->attributes = 0;
        }

        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        return SZW_ERROR_FAIL;
    }
}

// Helper function for C++ API extraction (with password support)
int ArchiveReader::extractToFile_CPP(uint32_t index, const char* output_path) {
    try {
        CMyComPtr<IInArchive> archive;

        // Check if we already have a cached archive open
        if (fileArchive) {
            // Reuse the cached archive
            archive = static_cast<IInArchive*>(fileArchive);
            archive->AddRef();  // AddRef since CMyComPtr will Release on destruction
        } else {
            // First time opening - create and cache the archive
            // Initialize 7z format GUID
            GUID CLSID_Format7z;
            Init7zFormatGUID(&CLSID_Format7z);

            // Create 7z archive handler
            HRESULT hr = CreateArchiver(&CLSID_Format7z, &IID_IInArchive, (void**)&archive);
            if (hr != S_OK || !archive) {
                errorMessage = "Failed to create 7z handler";
                return SZW_ERROR_FAIL;
            }

            // Open file stream
            CInFileStream *fileSpec = new CInFileStream;
            CMyComPtr<IInStream> file = fileSpec;

            // Convert path to FString (platform-appropriate string type)
            FString archivePathFS = us2fs(GetUnicodeString(archivePath.c_str()));
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
                snprintf(errBuf, sizeof(errBuf), "Failed to open archive with C++ API (HRESULT: 0x%08X)", (unsigned int)hr);
                errorMessage = errBuf;
                return SZW_ERROR_OPEN_FAILED;
            }

            // Cache the opened archive and stream for reuse
            archive->AddRef();
            fileArchive = archive.Detach();
            archive = static_cast<IInArchive*>(fileArchive);
            archive->AddRef();  // AddRef for the local CMyComPtr

            file->AddRef();
            fileStream = file.Detach();
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

    if (index >= pImpl->db.NumFiles) {
        errorMessage = "Index out of range";
        return SZW_ERROR_INVALIDARG;
    }

    if (!output_path) {
        errorMessage = "Output path is null";
        return SZW_ERROR_INVALIDARG;
    }

    // Check if this is a directory
    if (SzArEx_IsDir(&pImpl->db, index)) {
        errorMessage = "Cannot extract directory to file";
        return SZW_ERROR_INVALIDARG;
    }

    // If we have a cached C++ archive (password-protected), use it directly
    if (fileArchive) {
        return extractToFile_CPP(index, output_path);
    }

    // Otherwise use C API for unencrypted files
    try {
        UInt32 blockIndex = 0xFFFFFFFF; // Start with invalid block index
        Byte *outBuffer = nullptr;
        size_t outBufferSize = 0;
        size_t offset = 0;
        size_t outSizeProcessed = 0;

        // Extract file to memory buffer
        SRes res = SzArEx_Extract(&pImpl->db, &pImpl->lookStream.vt, index,
                                  &blockIndex, &outBuffer, &outBufferSize,
                                  &offset, &outSizeProcessed,
                                  &pImpl->allocImp, &pImpl->allocTempImp);

        if (res != SZ_OK) {
            errorMessage = "Failed to extract file";
            if (outBuffer) {
                ISzAlloc_Free(&pImpl->allocImp, outBuffer);
            }
            return SZW_ERROR_EXTRACT_FAILED;
        }

        // Open output file
        CSzFile outFile;
        WRes wres = OutFile_Open(&outFile, output_path);
        if (wres != 0) {
            errorMessage = "Failed to create output file";
            if (outBuffer) {
                ISzAlloc_Free(&pImpl->allocImp, outBuffer);
            }
            return SZW_ERROR_WRITE_FAILED;
        }

        // Write extracted data to file
        size_t processedSize = outSizeProcessed;
        wres = File_Write(&outFile, outBuffer + offset, &processedSize);

        // Free the buffer
        ISzAlloc_Free(&pImpl->allocImp, outBuffer);

        if (wres != 0 || processedSize != outSizeProcessed) {
            File_Close(&outFile);
            errorMessage = "Failed to write output file";
            return SZW_ERROR_WRITE_FAILED;
        }

        // Close the output file
        wres = File_Close(&outFile);
        if (wres != 0) {
            errorMessage = "Failed to close output file";
            return SZW_ERROR_WRITE_FAILED;
        }

        return SZW_OK;

    } catch (const std::exception& e) {
        errorMessage = e.what();
        return SZW_ERROR_FAIL;
    }
}

int ArchiveReader::extractToMemory(uint32_t index, uint8_t** buffer, size_t* size) {
    if (!pImpl->isOpen) {
        errorMessage = "Archive not open";
        return SZW_ERROR_FAIL;
    }

    try {
        // Initialize 7z format GUID
        GUID CLSID_Format7z;
        Init7zFormatGUID(&CLSID_Format7z);

        // Create 7z archive handler
        CMyComPtr<IInArchive> archive;
        HRESULT hr = CreateArchiver(&CLSID_Format7z, &IID_IInArchive, (void**)&archive);
        if (hr != S_OK || !archive) {
            errorMessage = "Failed to create 7z handler";
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
            if (index >= pImpl->db.NumFiles) {
                errorMessage = "Index out of range";
                return SZW_ERROR_INVALIDARG;
            }

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
            errorMessage = "Failed to open archive";
            return SZW_ERROR_OPEN_FAILED;
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
        hr = archive->Extract(indices, 1, 0, extractCallback);

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
        // Initialize 7z format GUID
        GUID CLSID_Format7z;
        Init7zFormatGUID(&CLSID_Format7z);

        // Create 7z archive handler
        CMyComPtr<IInArchive> archive;
        HRESULT hr = CreateArchiver(&CLSID_Format7z, &IID_IInArchive, (void**)&archive);
        if (hr != S_OK || !archive) {
            errorMessage = "Failed to create 7z handler";
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

        // If this is a file-based archive (not memory-based) and we don't have a C++ archive yet,
        // open it now with the C++ API for better extraction performance
        if (!isMemoryBased && !fileArchive && !archivePath.empty()) {

            // Initialize 7z format GUID
            GUID CLSID_Format7z;
            Init7zFormatGUID(&CLSID_Format7z);

            // Create 7z archive handler
            CMyComPtr<IInArchive> archive;
            HRESULT hr = CreateArchiver(&CLSID_Format7z, &IID_IInArchive, (void**)&archive);
            if (hr != S_OK || !archive) {
                errorMessage = "Failed to create 7z handler";
                return SZW_ERROR_FAIL;
            }

            // Open file stream
            CInFileStream *fileSpec = new CInFileStream;
            CMyComPtr<IInStream> file = fileSpec;

            FString archivePathFS = us2fs(GetUnicodeString(archivePath.c_str()));
            if (!fileSpec->Open(archivePathFS)) {
                errorMessage = "Failed to open archive file";
                return SZW_ERROR_OPEN_FAILED;
            }

            // Create open callback with password
            CArchiveOpenCallback *openCallbackSpec = new CArchiveOpenCallback;
            CMyComPtr<IArchiveOpenCallback> openCallback(openCallbackSpec);
            openCallbackSpec->SetPassword(password.c_str());

            // Open archive
            const UInt64 scanSize = 1 << 23;
            hr = archive->Open(file, &scanSize, openCallback);
            if (hr != S_OK) {
                char errBuf[256];
                snprintf(errBuf, sizeof(errBuf), "Failed to open password-protected archive (HRESULT: 0x%08X)", (unsigned int)hr);
                errorMessage = errBuf;
                return SZW_ERROR_OPEN_FAILED;
            }

            // Cache the archive and stream for extraction
            archive->AddRef();
            fileArchive = archive.Detach();

            file->AddRef();
            fileStream = file.Detach();
        }
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
        // Initialize 7z format GUID using shared definition
        GUID CLSID_Format7z;
        Init7zFormatGUID(&CLSID_Format7z);

        // Create output archive handler
        CMyComPtr<IOutArchive> outArchive;
        HRESULT hr = CreateArchiver(&CLSID_Format7z, &IID_IOutArchive, (void**)&outArchive);
        if (hr != S_OK || !outArchive) {
            errorMessage = "Failed to create 7z output handler";
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
