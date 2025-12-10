/* cpp_bridge.hpp - C++ to C bridge header
 * This file defines C++ classes and functions that interface with the LZMA SDK (7-Zip)
 */

#ifndef CPP_BRIDGE_HPP
#define CPP_BRIDGE_HPP

#include "lzma_sdk_wrapper.h"

#include <string>
#include <vector>
#include <memory>

/* 7-Zip SDK includes */
extern "C" {
    #include "lzma_sdk/C/7z.h"
    #include "lzma_sdk/C/7zAlloc.h"
    #include "lzma_sdk/C/7zCrc.h"
    #include "lzma_sdk/C/7zFile.h"
    #include "lzma_sdk/C/7zVersion.h"
}

namespace LzmaSdkWrapper {

/**
 * Archive handle implementation
 * This is the actual C++ object hidden behind the void* handle
 */
class ArchiveHandle {
public:
    virtual ~ArchiveHandle() = default;

    virtual uint32_t getEntryCount() = 0;
    virtual int getEntryInfo(uint32_t index, SzEntryInfo* info) = 0;
    virtual int extractToFile(uint32_t index, const char* output_path) = 0;
    virtual int extractToMemory(uint32_t index, uint8_t** buffer, size_t* size) = 0;
    virtual int verify() = 0;
    virtual int setPassword(const char* password) = 0;
    virtual int setProgressCallback(SzProgressCallback callback, void* user_data) = 0;
    virtual const char* getErrorMessage() = 0;
};

/**
 * Reader implementation for extracting archives
 */
class ArchiveReader : public ArchiveHandle {
public:
    ArchiveReader();
    ~ArchiveReader() override;

    int open(const char* path, int format);
    int openFromMemory(const uint8_t* data, size_t size, int format);
    void close();

    uint32_t getEntryCount() override;
    int getEntryInfo(uint32_t index, SzEntryInfo* info) override;
    int extractToFile(uint32_t index, const char* output_path) override;
    int extractToMemory(uint32_t index, uint8_t** buffer, size_t* size) override;
    int verify() override;
    int setPassword(const char* password) override;
    int setProgressCallback(SzProgressCallback callback, void* user_data) override;
    const char* getErrorMessage() override;

private:
    // Helper for C++ API extraction with password support
    int extractToFile_CPP(uint32_t index, const char* output_path);

    class Impl;
    std::unique_ptr<Impl> pImpl;
    std::string errorMessage;
    std::string password;
    std::string archivePath;  // Store archive path for C++ API reopening
    SzProgressCallback progressCallback;
    void* progressUserData;

    // Memory-based archive support
    bool isMemoryBased;
    std::vector<uint8_t> memoryBuffer;  // Owned copy of archive data
    void* memoryArchive;  // IInArchive pointer for memory-based archives

    // File-based C++ API cache (for password-protected archives)
    void* fileArchive;  // IInArchive pointer cached for file-based password extraction
    void* fileStream;   // IInStream pointer cached for file-based password extraction
};

/**
 * Writer implementation for creating archives
 */
class ArchiveWriter : public ArchiveHandle {
public:
    ArchiveWriter();
    ~ArchiveWriter() override;

    int create(const char* path, int format, const SzCompressionOptions* options);
    void close();

    int addFile(const char* src_path, const char* archive_path);
    int addDirectory(const char* src_path, const char* archive_path);
    int addData(const uint8_t* data, size_t size, const char* archive_path);
    int mkdir(const char* archive_path);

    /* Not used for writing */
    uint32_t getEntryCount() override { return 0; }
    int getEntryInfo(uint32_t index, SzEntryInfo* info) override { return SZW_ERROR_UNSUPPORTED_FORMAT; }
    int extractToFile(uint32_t index, const char* output_path) override { return SZW_ERROR_UNSUPPORTED_FORMAT; }
    int extractToMemory(uint32_t index, uint8_t** buffer, size_t* size) override { return SZW_ERROR_UNSUPPORTED_FORMAT; }
    int verify() override { return SZW_ERROR_UNSUPPORTED_FORMAT; }

    int setPassword(const char* password) override;
    int setProgressCallback(SzProgressCallback callback, void* user_data) override;
    const char* getErrorMessage() override;

private:
    class Impl;
    std::unique_ptr<Impl> pImpl;
    std::string errorMessage;
    std::string password;
    SzProgressCallback progressCallback;
    void* progressUserData;
#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-private-field"
#endif
    SzCompressionOptions options;  // Reserved for future compression support
#ifdef __clang__
#pragma clang diagnostic pop
#endif
};

} // namespace LzmaSdkWrapper

#endif /* CPP_BRIDGE_HPP */
