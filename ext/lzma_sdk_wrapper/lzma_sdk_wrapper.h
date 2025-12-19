/* lzma_sdk_wrapper.h - C interface for LZMA SDK (7-Zip)
 * This header defines a C-compatible interface for Ruby FFI bindings
 */

#ifndef LZMA_SDK_WRAPPER_H
#define LZMA_SDK_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/* ========== Constants ========== */

/* Error codes - prefixed with SZW_ to avoid collision with SDK */
#define SZW_OK 0
#define SZW_ERROR_FAIL 1
#define SZW_ERROR_OUTOFMEMORY 2
#define SZW_ERROR_INVALIDARG 3
#define SZW_ERROR_OPEN_FAILED 4
#define SZW_ERROR_READ_FAILED 5
#define SZW_ERROR_WRITE_FAILED 6
#define SZW_ERROR_EXTRACT_FAILED 7
#define SZW_ERROR_COMPRESS_FAILED 8
#define SZW_ERROR_PASSWORD_REQUIRED 9
#define SZW_ERROR_PASSWORD_INCORRECT 10
#define SZW_ERROR_CORRUPT_ARCHIVE 11
#define SZW_ERROR_UNSUPPORTED_FORMAT 12

/* Archive formats */
#define SZ_FORMAT_7Z 0
#define SZ_FORMAT_ZIP 1
#define SZ_FORMAT_TAR 2

/* Compression methods */
#define SZ_METHOD_LZMA 0
#define SZ_METHOD_LZMA2 1
#define SZ_METHOD_PPMD 2
#define SZ_METHOD_BZIP2 3
#define SZ_METHOD_DEFLATE 4

/* Compression levels */
#define SZ_LEVEL_STORE 0
#define SZ_LEVEL_FASTEST 1
#define SZ_LEVEL_FAST 3
#define SZ_LEVEL_NORMAL 5
#define SZ_LEVEL_MAXIMUM 7
#define SZ_LEVEL_ULTRA 9

/* ========== Structures ========== */

/* Entry information */
typedef struct {
    char name[1024];           /* Entry name/path */
    uint64_t size;             /* Uncompressed size */
    uint64_t compressed_size;  /* Compressed size */
    uint32_t crc;              /* CRC32 checksum */
    uint64_t modified_time;    /* Unix timestamp */
    bool is_directory;         /* Is this a directory? */
    uint32_t attributes;       /* File attributes */
} SzEntryInfo;

/* Compression options */
typedef struct {
    int method;                /* Compression method (SZ_METHOD_*) */
    int level;                 /* Compression level (0-9) */
    int threads;               /* Number of threads (0 = auto) */
    uint32_t dictionary_size;  /* Dictionary size in bytes */
    bool solid;                /* Use solid compression */
} SzCompressionOptions;

/* Progress callback: returns 0 to continue, non-zero to cancel */
typedef int (*SzProgressCallback)(uint64_t completed, uint64_t total, void* user_data);

/* ========== Archive Operations ========== */

/**
 * Open an archive for reading
 *
 * @param path Path to archive file
 * @param format Archive format (SZ_FORMAT_*)
 * @param error_code Output parameter for error code
 * @return Opaque handle to archive, or NULL on error
 */
void* sz_open_archive(const char* path, int format, int* error_code);

/**
 * Open an archive from memory buffer
 *
 * @param data Memory buffer containing archive data
 * @param size Size of buffer in bytes
 * @param format Archive format (SZ_FORMAT_*)
 * @param error_code Output parameter for error code
 * @return Opaque handle to archive, or NULL on error
 */
void* sz_open_from_memory(const uint8_t* data, size_t size, int format, int* error_code);

/**
 * Close an archive handle
 *
 * @param handle Archive handle from sz_open_archive or sz_create_archive
 * @return Error code (SZ_OK on success)
 */
int sz_close_archive(void* handle);

/**
 * Get number of entries in archive
 *
 * @param handle Archive handle
 * @return Number of entries, or 0 on error
 */
uint32_t sz_get_entry_count(void* handle);

/**
 * Get information about an entry
 *
 * @param handle Archive handle
 * @param index Entry index (0-based)
 * @param info Output parameter for entry information
 * @return Error code (SZ_OK on success)
 */
int sz_get_entry_info(void* handle, uint32_t index, SzEntryInfo* info);

/* ========== Extraction Operations ========== */

/**
 * Extract an entry to a file
 *
 * @param handle Archive handle
 * @param index Entry index
 * @param output_path Destination file path
 * @return Error code (SZ_OK on success)
 */
int sz_extract_to_file(void* handle, uint32_t index, const char* output_path);

/**
 * Extract an entry to memory
 *
 * @param handle Archive handle
 * @param index Entry index
 * @param buffer Output parameter for data buffer (caller must free)
 * @param size Output parameter for buffer size
 * @return Error code (SZ_OK on success)
 */
int sz_extract_to_memory(void* handle, uint32_t index, uint8_t** buffer, size_t* size);

/**
 * Verify archive integrity
 *
 * @param handle Archive handle
 * @return Error code (SZ_OK if archive is valid)
 */
int sz_verify(void* handle);

/* ========== Compression Operations ========== */

/**
 * Create a new archive for writing
 *
 * @param path Output archive path
 * @param format Archive format (SZ_FORMAT_*)
 * @param options Compression options (NULL for defaults)
 * @return Opaque handle to archive, or NULL on error
 */
void* sz_create_archive(const char* path, int format, const SzCompressionOptions* options);

/**
 * Add a file to archive
 *
 * @param handle Archive handle
 * @param src_path Source file path
 * @param archive_path Path within archive
 * @return Error code (SZ_OK on success)
 */
int sz_add_file(void* handle, const char* src_path, const char* archive_path);

/**
 * Add a directory to archive (recursively)
 *
 * @param handle Archive handle
 * @param src_path Source directory path
 * @param archive_path Path within archive
 * @return Error code (SZ_OK on success)
 */
int sz_add_directory(void* handle, const char* src_path, const char* archive_path);

/**
 * Add data from memory to archive
 *
 * @param handle Archive handle
 * @param data Data buffer
 * @param size Data size
 * @param archive_path Path within archive
 * @return Error code (SZ_OK on success)
 */
int sz_add_data(void* handle, const uint8_t* data, size_t size, const char* archive_path);

/**
 * Create an empty directory in archive
 *
 * @param handle Archive handle
 * @param archive_path Directory path within archive
 * @return Error code (SZ_OK on success)
 */
int sz_mkdir(void* handle, const char* archive_path);

/* ========== Advanced Operations ========== */

/**
 * Set password for encryption/decryption
 *
 * @param handle Archive handle
 * @param password Password string (NULL to clear)
 * @return Error code (SZ_OK on success)
 */
int sz_set_password(void* handle, const char* password);

/**
 * Set progress callback
 *
 * @param handle Archive handle
 * @param callback Callback function (NULL to clear)
 * @param user_data User data passed to callback
 * @return Error code (SZ_OK on success)
 */
int sz_set_progress_callback(void* handle, SzProgressCallback callback, void* user_data);

/**
 * Get last error message
 *
 * @param handle Archive handle
 * @return Error message string (valid until next operation)
 */
const char* sz_get_error_message(void* handle);

/**
 * Free memory allocated by the library
 *
 * Use this to free memory returned by sz_extract_to_memory.
 *
 * @param ptr Pointer to memory to free
 */
void sz_free(void* ptr);

/**
 * Get LZMA SDK version
 *
 * @return Version string (e.g., "25.01")
 */
const char* sz_get_version(void);

/**
 * Get LZMA SDK full version info with copyright
 *
 * @return Version info string with copyright and date
 */
const char* sz_get_sdk_info(void);

#ifdef __cplusplus
}
#endif

#endif /* LZMA_SDK_WRAPPER_H */
