// archive_callbacks.cpp
// Implementation of C++ callback classes for 7-Zip COM API

#include "archive_callbacks.hpp"
#include "lzma_sdk/CPP/Common/StringConvert.h"
#include "lzma_sdk/CPP/7zip/Archive/IArchive.h"
#include "lzma_sdk/CPP/Windows/FileDir.h"
#include "lzma_sdk/CPP/Windows/FileFind.h"
#include "lzma_sdk/CPP/Windows/FileName.h"

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
