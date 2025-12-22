// archive_callbacks.cpp
// Implementation of C++ callback classes for 7-Zip COM API

#include "archive_callbacks.hpp"
#include "lzma_sdk/CPP/Common/StringConvert.h"
#include "lzma_sdk/CPP/7zip/Archive/IArchive.h"
#include "lzma_sdk/CPP/Windows/FileDir.h"
#include "lzma_sdk/CPP/Windows/FileFind.h"
#include "lzma_sdk/CPP/Windows/FileName.h"
#include "lzma_sdk/CPP/Windows/PropVariant.h"

using namespace NWindows;
using namespace NFile;

// Helper function to convert C string to FString
static FString CmdStringToFString(const char *s)
{
  return us2fs(GetUnicodeString(s));
}

// CArchiveOpenCallback implementation

void CArchiveOpenCallback::SetPassword(const char* password)
{
  if (password && password[0] != '\0')
  {
    Password = GetUnicodeString(password);
    PasswordIsDefined = true;
  }
  else
  {
    Password.Empty();
    PasswordIsDefined = false;
  }
}

Z7_COM7F_IMF(CArchiveOpenCallback::SetTotal(const UInt64 * /* files */, const UInt64 * /* bytes */))
{
  return S_OK;
}

Z7_COM7F_IMF(CArchiveOpenCallback::SetCompleted(const UInt64 * /* files */, const UInt64 * /* bytes */))
{
  return S_OK;
}

Z7_COM7F_IMF(CArchiveOpenCallback::CryptoGetTextPassword(BSTR *password))
{
  if (!PasswordIsDefined)
  {
    // No password provided
    return E_ABORT;
  }
  return StringToBstr(Password, password);
}

// CArchiveExtractCallback implementation

void CArchiveExtractCallback::Init(IInArchive *archiveHandler, UInt32 index, const char* outputPath)
{
  _archiveHandler = archiveHandler;
  _index = index;
  _outputPath = outputPath;
  _numErrors = 0;
}

void CArchiveExtractCallback::SetPassword(const char* password)
{
  if (password && password[0] != '\0')
  {
    Password = GetUnicodeString(password);
    PasswordIsDefined = true;
  }
  else
  {
    Password.Empty();
    PasswordIsDefined = false;
  }
}

Z7_COM7F_IMF(CArchiveExtractCallback::SetTotal(UInt64 /* size */))
{
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallback::SetCompleted(const UInt64 * /* completeValue */))
{
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallback::GetStream(UInt32 index,
    ISequentialOutStream **outStream, Int32 askExtractMode))
{
  *outStream = nullptr;
  _outFileStream.Release();

  if (askExtractMode != NArchive::NExtract::NAskMode::kExtract)
  {
    return S_OK;
  }

  // Only handle the requested index
  if (index != _index)
  {
    return S_OK;
  }

  // Create output file stream
  _outFileStreamSpec = new COutFileStream;
  CMyComPtr<ISequentialOutStream> outStreamLoc(_outFileStreamSpec);

  FString fullPath = CmdStringToFString(_outputPath);

  // Create parent directories if needed
  {
    int slashPos = fullPath.ReverseFind_PathSepar();
    if (slashPos >= 0)
    {
      FString dirPath = fullPath.Left(slashPos);
      NDir::CreateComplexDir(dirPath);
    }
  }

  // Delete existing file if present
  {
    NFind::CFileInfo fi;
    if (fi.Find(fullPath))
    {
      if (!NDir::DeleteFileAlways(fullPath))
      {
        return E_FAIL;
      }
    }
  }

  if (!_outFileStreamSpec->Create_ALWAYS(fullPath))
  {
    return E_FAIL;
  }

  _outFileStream = outStreamLoc;
  *outStream = outStreamLoc.Detach();
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallback::PrepareOperation(Int32 askExtractMode))
{
  _extractMode = (askExtractMode == NArchive::NExtract::NAskMode::kExtract);
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallback::SetOperationResult(Int32 operationResult))
{
  if (operationResult != NArchive::NExtract::NOperationResult::kOK)
  {
    _numErrors++;
  }

  if (_outFileStream)
  {
    if (_outFileStreamSpec->Close() != S_OK)
      _numErrors++;
  }
  _outFileStream.Release();

  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallback::CryptoGetTextPassword(BSTR *password))
{
  if (!PasswordIsDefined)
  {
    // No password provided
    return E_ABORT;
  }
  return StringToBstr(Password, password);
}

// CArchiveExtractCallbackMemory implementation

void CArchiveExtractCallbackMemory::Init(IInArchive *archiveHandler, UInt32 index, ISequentialOutStream *outStream)
{
  _archiveHandler = archiveHandler;
  _index = index;
  _outStream = outStream;
  _numErrors = 0;
}

void CArchiveExtractCallbackMemory::SetPassword(const char* password)
{
  if (password && password[0] != '\0')
  {
    Password = GetUnicodeString(password);
    PasswordIsDefined = true;
  }
  else
  {
    Password.Empty();
    PasswordIsDefined = false;
  }
}

Z7_COM7F_IMF(CArchiveExtractCallbackMemory::SetTotal(UInt64 /* size */))
{
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallbackMemory::SetCompleted(const UInt64 * /* completeValue */))
{
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallbackMemory::GetStream(UInt32 index,
    ISequentialOutStream **outStream, Int32 askExtractMode))
{
  *outStream = nullptr;

  if (askExtractMode != NArchive::NExtract::NAskMode::kExtract)
  {
    return S_OK;
  }

  // Only handle the requested index
  if (index != _index)
  {
    return S_OK;
  }

  // Return the pre-configured output stream
  *outStream = _outStream;
  _outStream->AddRef();
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallbackMemory::PrepareOperation(Int32 askExtractMode))
{
  _extractMode = (askExtractMode == NArchive::NExtract::NAskMode::kExtract);
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallbackMemory::SetOperationResult(Int32 operationResult))
{
  if (operationResult != NArchive::NExtract::NOperationResult::kOK)
  {
    _numErrors++;
  }
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallbackMemory::CryptoGetTextPassword(BSTR *password))
{
  if (!PasswordIsDefined)
  {
    // No password provided
    return E_ABORT;
  }
  return StringToBstr(Password, password);
}

// CArchiveExtractCallbackVerify implementation

void CArchiveExtractCallbackVerify::Init(IInArchive *archiveHandler)
{
  _archiveHandler = archiveHandler;
  _numErrors = 0;
}

void CArchiveExtractCallbackVerify::SetPassword(const char* password)
{
  if (password && password[0] != '\0')
  {
    Password = GetUnicodeString(password);
    PasswordIsDefined = true;
  }
  else
  {
    Password.Empty();
    PasswordIsDefined = false;
  }
}

Z7_COM7F_IMF(CArchiveExtractCallbackVerify::SetTotal(UInt64 /* size */))
{
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallbackVerify::SetCompleted(const UInt64 * /* completeValue */))
{
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallbackVerify::GetStream(UInt32 /* index */,
    ISequentialOutStream **outStream, Int32 /* askExtractMode */))
{
  // For verification, we don't need to extract to anywhere
  *outStream = nullptr;
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallbackVerify::PrepareOperation(Int32 /* askExtractMode */))
{
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallbackVerify::SetOperationResult(Int32 operationResult))
{
  if (operationResult != NArchive::NExtract::NOperationResult::kOK)
  {
    _numErrors++;
  }
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallbackVerify::CryptoGetTextPassword(BSTR *password))
{
  if (!PasswordIsDefined)
  {
    // No password provided
    return E_ABORT;
  }
  return StringToBstr(Password, password);
}

// ==================== CArchiveUpdateCallback Implementation ====================

// Memory stream for reading in-memory data
class CMemoryReadStream Z7_final:
  public ISequentialInStream,
  public CMyUnknownImp
{
  Z7_COM_UNKNOWN_IMP_1(ISequentialInStream)
  Z7_IFACE_COM7_IMP(ISequentialInStream)

  const Byte *_data;
  UInt64 _size;
  UInt64 _pos;

public:
  CMemoryReadStream(const Byte *data, UInt64 size) : _data(data), _size(size), _pos(0) {}
};

Z7_COM7F_IMF(CMemoryReadStream::Read(void *data, UInt32 size, UInt32 *processedSize))
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

void CArchiveUpdateCallback::Init(const std::vector<CArchiveItem> *items)
{
  _items = items;
  _numErrors = 0;
}

void CArchiveUpdateCallback::SetPassword(const char* password)
{
  if (password && password[0] != '\0')
  {
    Password = GetUnicodeString(password);
    PasswordIsDefined = true;
  }
  else
  {
    Password.Empty();
    PasswordIsDefined = false;
  }
}

Z7_COM7F_IMF(CArchiveUpdateCallback::SetTotal(UInt64 /* size */))
{
  return S_OK;
}

Z7_COM7F_IMF(CArchiveUpdateCallback::SetCompleted(const UInt64 * /* completeValue */))
{
  return S_OK;
}

Z7_COM7F_IMF(CArchiveUpdateCallback::GetUpdateItemInfo(UInt32 /* index */,
    Int32 *newData, Int32 *newProperties, UInt32 *indexInArchive))
{
  // Always new data for a new archive
  if (newData)
    *newData = BoolToInt(true);
  if (newProperties)
    *newProperties = BoolToInt(true);
  if (indexInArchive)
    *indexInArchive = (UInt32)(Int32)-1;  // Not in existing archive
  return S_OK;
}

Z7_COM7F_IMF(CArchiveUpdateCallback::GetProperty(UInt32 index, PROPID propID, PROPVARIANT *value))
{
  NWindows::NCOM::CPropVariant prop;

  if (propID == kpidIsAnti)
  {
    prop = false;
    prop.Detach(value);
    return S_OK;
  }

  if (!_items || index >= _items->size())
  {
    return E_INVALIDARG;
  }

  const CArchiveItem &item = (*_items)[index];

  switch (propID)
  {
    case kpidPath:
      prop = item.Path;
      break;
    case kpidIsDir:
      prop = item.IsDir;
      break;
    case kpidSize:
      prop = item.Size;
      break;
    case kpidAttrib:
      prop = item.IsDir ? (UInt32)0x10 : (UInt32)0x20;  // FILE_ATTRIBUTE_DIRECTORY or FILE_ATTRIBUTE_ARCHIVE
      break;
  }

  prop.Detach(value);
  return S_OK;
}

Z7_COM7F_IMF(CArchiveUpdateCallback::GetStream(UInt32 index, ISequentialInStream **inStream))
{
  *inStream = nullptr;

  if (!_items || index >= _items->size())
  {
    return E_INVALIDARG;
  }

  const CArchiveItem &item = (*_items)[index];

  // Directories don't have streams
  if (item.IsDir)
  {
    return S_OK;
  }

  if (item.IsFromMemory)
  {
    // Create memory stream
    CMemoryReadStream *streamSpec = new CMemoryReadStream(
        item.Data.data(), item.Data.size());
    CMyComPtr<ISequentialInStream> streamLoc(streamSpec);
    *inStream = streamLoc.Detach();
  }
  else
  {
    // Create file stream
    CInFileStream *inStreamSpec = new CInFileStream;
    CMyComPtr<ISequentialInStream> streamLoc(inStreamSpec);

    if (!inStreamSpec->Open(item.FullPath))
    {
      _numErrors++;
      return S_FALSE;
    }

    *inStream = streamLoc.Detach();
  }

  return S_OK;
}

Z7_COM7F_IMF(CArchiveUpdateCallback::SetOperationResult(Int32 /* operationResult */))
{
  return S_OK;
}

Z7_COM7F_IMF(CArchiveUpdateCallback::GetVolumeSize(UInt32 /* index */, UInt64 * /* size */))
{
  return S_FALSE;  // No volume splitting
}

Z7_COM7F_IMF(CArchiveUpdateCallback::GetVolumeStream(UInt32 /* index */, ISequentialOutStream ** /* volumeStream */))
{
  return S_FALSE;  // No volume splitting
}

Z7_COM7F_IMF(CArchiveUpdateCallback::CryptoGetTextPassword2(Int32 *passwordIsDefined, BSTR *password))
{
  *passwordIsDefined = BoolToInt(PasswordIsDefined);
  return StringToBstr(Password, password);
}