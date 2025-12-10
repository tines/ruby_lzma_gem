// archive_callbacks.hpp
// C++ callback classes for 7-Zip COM API with password support

#ifndef ARCHIVE_CALLBACKS_HPP
#define ARCHIVE_CALLBACKS_HPP

#include "lzma_sdk/CPP/7zip/Archive/IArchive.h"
#include "lzma_sdk/CPP/7zip/IPassword.h"
#include "lzma_sdk/CPP/Common/MyCom.h"
#include "lzma_sdk/CPP/Common/MyString.h"
#include "lzma_sdk/CPP/7zip/Common/FileStreams.h"

// Archive open callback with password support
class CArchiveOpenCallback Z7_final:
  public IArchiveOpenCallback,
  public ICryptoGetTextPassword,
  public CMyUnknownImp
{
  Z7_IFACES_IMP_UNK_2(IArchiveOpenCallback, ICryptoGetTextPassword)

public:
  bool PasswordIsDefined;
  UString Password;

  CArchiveOpenCallback() : PasswordIsDefined(false) {}
  void SetPassword(const char* password);
};

// Archive extract callback with password support
class CArchiveExtractCallback Z7_final:
  public IArchiveExtractCallback,
  public ICryptoGetTextPassword,
  public CMyUnknownImp
{
  Z7_IFACES_IMP_UNK_2(IArchiveExtractCallback, ICryptoGetTextPassword)
  Z7_IFACE_COM7_IMP(IProgress)

  CMyComPtr<IInArchive> _archiveHandler;
  UInt32 _index;           // Index of file being extracted
  const char* _outputPath; // Output file path
  COutFileStream *_outFileStreamSpec;
  CMyComPtr<ISequentialOutStream> _outFileStream;
  bool _extractMode;
  UInt64 _numErrors;

public:
  bool PasswordIsDefined;
  UString Password;

  CArchiveExtractCallback() :
    _index(0),
    _outputPath(nullptr),
    _outFileStreamSpec(nullptr),
    _extractMode(false),
    _numErrors(0),
    PasswordIsDefined(false) {}

  void Init(IInArchive *archiveHandler, UInt32 index, const char* outputPath);
  void SetPassword(const char* password);
  UInt64 GetNumErrors() const { return _numErrors; }
};

// Archive extract callback for extracting to memory
class CArchiveExtractCallbackMemory Z7_final:
  public IArchiveExtractCallback,
  public ICryptoGetTextPassword,
  public CMyUnknownImp
{
  Z7_IFACES_IMP_UNK_2(IArchiveExtractCallback, ICryptoGetTextPassword)
  Z7_IFACE_COM7_IMP(IProgress)

  CMyComPtr<IInArchive> _archiveHandler;
  UInt32 _index;           // Index of file being extracted
  CMyComPtr<ISequentialOutStream> _outStream;
  bool _extractMode;
  UInt64 _numErrors;

public:
  bool PasswordIsDefined;
  UString Password;

  CArchiveExtractCallbackMemory() :
    _index(0),
    _extractMode(false),
    _numErrors(0),
    PasswordIsDefined(false) {}

  void Init(IInArchive *archiveHandler, UInt32 index, ISequentialOutStream *outStream);
  void SetPassword(const char* password);
  UInt64 GetNumErrors() const { return _numErrors; }
};

// Archive extract callback for verification (test mode)
class CArchiveExtractCallbackVerify Z7_final:
  public IArchiveExtractCallback,
  public ICryptoGetTextPassword,
  public CMyUnknownImp
{
  Z7_IFACES_IMP_UNK_2(IArchiveExtractCallback, ICryptoGetTextPassword)
  Z7_IFACE_COM7_IMP(IProgress)

  CMyComPtr<IInArchive> _archiveHandler;
  UInt64 _numErrors;

public:
  bool PasswordIsDefined;
  UString Password;

  CArchiveExtractCallbackVerify() :
    _numErrors(0),
    PasswordIsDefined(false) {}

  void Init(IInArchive *archiveHandler);
  void SetPassword(const char* password);
  UInt64 GetNumErrors() const { return _numErrors; }
};

#endif // ARCHIVE_CALLBACKS_HPP
