/* lzma_sdk_wrapper.c - C wrapper implementation
 * This file provides C-compatible wrappers that call into C++ bridge
 */

#include "lzma_sdk_wrapper.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Forward declarations from C++ bridge */
#ifdef __cplusplus
extern "C" {
#endif

/* These will be implemented in cpp_bridge.cpp */
void* cpp_open_archive(const char* path, int format, int* error_code);
void* cpp_open_archive_from_memory(const uint8_t* data, size_t size, int format, int* error_code);
int cpp_close_archive(void* handle);
uint32_t cpp_get_entry_count(void* handle);
int cpp_get_entry_info(void* handle, uint32_t index, SzEntryInfo* info);
int cpp_extract_to_file(void* handle, uint32_t index, const char* output_path);
int cpp_extract_to_memory(void* handle, uint32_t index, uint8_t** buffer, size_t* size);
int cpp_verify(void* handle);
void* cpp_create_archive(const char* path, int format, const SzCompressionOptions* options);
int cpp_add_file(void* handle, const char* src_path, const char* archive_path);
int cpp_add_directory(void* handle, const char* src_path, const char* archive_path);
int cpp_add_data(void* handle, const uint8_t* data, size_t size, const char* archive_path);
int cpp_mkdir(void* handle, const char* archive_path);
int cpp_set_password(void* handle, const char* password);
int cpp_set_progress_callback(void* handle, SzProgressCallback callback, void* user_data);
const char* cpp_get_error_message(void* handle);

#ifdef __cplusplus
}
#endif

/* ========== Archive Operations ========== */

void* sz_open_archive(const char* path, int format, int* error_code) {
    if (!path || !error_code) {
        if (error_code) *error_code = SZW_ERROR_INVALIDARG;
        return NULL;
    }

    return cpp_open_archive(path, format, error_code);
}

void* sz_open_from_memory(const uint8_t* data, size_t size, int format, int* error_code) {
    if (!data || size == 0 || !error_code) {
        if (error_code) *error_code = SZW_ERROR_INVALIDARG;
        return NULL;
    }

    return cpp_open_archive_from_memory(data, size, format, error_code);
}

int sz_close_archive(void* handle) {
    if (!handle) {
        return SZW_ERROR_INVALIDARG;
    }

    return cpp_close_archive(handle);
}

uint32_t sz_get_entry_count(void* handle) {
    if (!handle) {
        return 0;
    }

    return cpp_get_entry_count(handle);
}

int sz_get_entry_info(void* handle, uint32_t index, SzEntryInfo* info) {
    if (!handle || !info) {
        return SZW_ERROR_INVALIDARG;
    }

    return cpp_get_entry_info(handle, index, info);
}

/* ========== Extraction Operations ========== */

int sz_extract_to_file(void* handle, uint32_t index, const char* output_path) {
    if (!handle || !output_path) {
        return SZW_ERROR_INVALIDARG;
    }

    return cpp_extract_to_file(handle, index, output_path);
}

int sz_extract_to_memory(void* handle, uint32_t index, uint8_t** buffer, size_t* size) {
    if (!handle || !buffer || !size) {
        return SZW_ERROR_INVALIDARG;
    }

    return cpp_extract_to_memory(handle, index, buffer, size);
}

int sz_verify(void* handle) {
    if (!handle) {
        return SZW_ERROR_INVALIDARG;
    }

    return cpp_verify(handle);
}

/* ========== Compression Operations ========== */

void* sz_create_archive(const char* path, int format, const SzCompressionOptions* options) {
    if (!path) {
        return NULL;
    }

    return cpp_create_archive(path, format, options);
}

int sz_add_file(void* handle, const char* src_path, const char* archive_path) {
    if (!handle || !src_path || !archive_path) {
        return SZW_ERROR_INVALIDARG;
    }

    return cpp_add_file(handle, src_path, archive_path);
}

int sz_add_directory(void* handle, const char* src_path, const char* archive_path) {
    if (!handle || !archive_path) {
        return SZW_ERROR_INVALIDARG;
    }

    return cpp_add_directory(handle, src_path, archive_path);
}

int sz_add_data(void* handle, const uint8_t* data, size_t size, const char* archive_path) {
    if (!handle || !data || !archive_path) {
        return SZW_ERROR_INVALIDARG;
    }

    return cpp_add_data(handle, data, size, archive_path);
}

int sz_mkdir(void* handle, const char* archive_path) {
    if (!handle || !archive_path) {
        return SZW_ERROR_INVALIDARG;
    }

    return cpp_mkdir(handle, archive_path);
}

/* ========== Advanced Operations ========== */

int sz_set_password(void* handle, const char* password) {
    if (!handle) {
        return SZW_ERROR_INVALIDARG;
    }

    return cpp_set_password(handle, password);
}

int sz_set_progress_callback(void* handle, SzProgressCallback callback, void* user_data) {
    if (!handle) {
        return SZW_ERROR_INVALIDARG;
    }

    return cpp_set_progress_callback(handle, callback, user_data);
}

const char* sz_get_error_message(void* handle) {
    if (!handle) {
        return "Invalid handle";
    }

    return cpp_get_error_message(handle);
}

/* ========== Memory Management ========== */

void sz_free(void* ptr) {
    if (ptr) {
        free(ptr);
    }
}

/* Include SDK version header */
#include "lzma_sdk/C/7zVersion.h"

const char* sz_get_version(void) {
    return MY_VERSION_NUMBERS;
}

const char* sz_get_sdk_info(void) {
    return MY_VERSION_COPYRIGHT_DATE;
}
