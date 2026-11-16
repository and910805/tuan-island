/* SPDX-License-Identifier: MIT */
#define _GNU_SOURCE
#include "gdextension_interface.h"
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
#define EXPORT __declspec(dllexport)
typedef wchar_t path_char;
typedef HANDLE NativeHandle;
#define INVALID_LOCK INVALID_HANDLE_VALUE
#define PATH_LITERAL(s) L##s
#else
#include <errno.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#define EXPORT __attribute__((visibility("default")))
typedef char path_char;
typedef int NativeHandle;
#define INVALID_LOCK (-1)
#define PATH_LITERAL(s) s
#endif

enum { OK = 0, OUT_OF_MEMORY = 6, FILE_CANT_OPEN = 12, INVALID_PARAMETER = 31, ALREADY_IN_USE = 22 };
typedef struct { NativeHandle handle; } Lock;
/* The 64-bit Godot API stores StringName and String as one pointer. */
typedef void *BuiltinString;
static GDExtensionClassLibraryPtr library;
static BuiltinString class_name, parent_name;
static GDExtensionInterfaceStringNameNewWithLatin1Chars new_name;
static GDExtensionInterfaceVariantGetPtrDestructor get_destructor;
static GDExtensionInterfaceGetVariantFromTypeConstructor from_variant_type;
static GDExtensionInterfaceGetVariantToTypeConstructor to_variant_type;
static GDExtensionInterfaceVariantGetType variant_type;
static GDExtensionInterfaceVariantDestroy destroy_variant;
static GDExtensionInterfaceVariantNewNil nil_variant;
static GDExtensionInterfaceClassdbConstructObject3 construct;
static GDExtensionInterfaceObjectSetInstance set_instance;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
#ifdef _WIN32
static GDExtensionInterfaceStringToWideChars path_chars;
#else
static GDExtensionInterfaceStringToUtf8Chars path_chars;
#endif

static void unlock(Lock *lock) {
    if (lock->handle == INVALID_LOCK) return;
#ifdef _WIN32
    CloseHandle(lock->handle);
#else
    close(lock->handle);
#endif
    lock->handle = INVALID_LOCK;
}

static int lock_path(Lock *lock, GDExtensionConstStringPtr string) {
    if (lock->handle != INVALID_LOCK) return ALREADY_IN_USE;
    const path_char suffix[] = PATH_LITERAL(".writer-lock");
    GDExtensionInt length = path_chars(string, NULL, 0);
    if (length <= (GDExtensionInt)(sizeof suffix / sizeof *suffix - 1) || length > 32767) return INVALID_PARAMETER;
    path_char *path = calloc((size_t)length + 1, sizeof *path);
    if (!path) return OUT_OF_MEMORY;
    path_chars(string, path, length);
    size_t suffix_length = sizeof suffix / sizeof *suffix - 1;
    int error = INVALID_PARAMETER;
    for (GDExtensionInt index = 0; index < length; index++) {
        if (!path[index]) goto done;
    }
    if (memcmp(path + length - suffix_length, suffix, suffix_length * sizeof *path)) goto done;
#ifdef _WIN32
    HANDLE handle = CreateFileW(path, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_ALWAYS,
                                FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (handle == INVALID_HANDLE_VALUE) {
        DWORD failure = GetLastError();
        error = failure == ERROR_SHARING_VIOLATION || failure == ERROR_LOCK_VIOLATION ? ALREADY_IN_USE : FILE_CANT_OPEN;
    } else {
        BY_HANDLE_FILE_INFORMATION information;
        if (!GetFileInformationByHandle(handle, &information) ||
            (information.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))) {
            CloseHandle(handle);
            error = FILE_CANT_OPEN;
        } else {
            lock->handle = handle;
            error = OK;
        }
    }
#else
    int fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0600);
    error = FILE_CANT_OPEN;
    if (fd >= 0) {
        struct stat info;
        if (fstat(fd, &info) == 0 && S_ISREG(info.st_mode)) {
            if (flock(fd, LOCK_EX | LOCK_NB) == 0) {
                lock->handle = fd;
                error = OK;
            } else if (errno == EWOULDBLOCK || errno == EAGAIN) {
                error = ALREADY_IN_USE;
            }
        }
        if (error != OK) close(fd);
    }
#endif
done:
    free(path);
    return error;
}

static GDExtensionObjectPtr create(void *userdata, GDExtensionBool notify) {
    (void)userdata;
    (void)notify;
    Lock *lock = malloc(sizeof *lock);
    if (!lock) return NULL;
    lock->handle = INVALID_LOCK;
    GDExtensionObjectPtr object = construct(&parent_name);
    set_instance(object, &class_name, lock);
    return object;
}

static void destroy(void *userdata, GDExtensionClassInstancePtr instance) {
    (void)userdata;
    unlock(instance);
    free(instance);
}

enum Method { ACQUIRE, RELEASE, IS_HELD };
static enum Method acquire_id = ACQUIRE, release_id = RELEASE, held_id = IS_HELD;

static void ptrcall(void *userdata, GDExtensionClassInstancePtr instance,
                    const GDExtensionConstTypePtr *args, GDExtensionTypePtr result) {
    Lock *lock = instance;
    switch (*(enum Method *)userdata) {
        case ACQUIRE: *(int64_t *)result = lock_path(lock, args[0]); break;
        case RELEASE: unlock(lock); break;
        case IS_HELD: *(GDExtensionBool *)result = lock->handle != INVALID_LOCK; break;
    }
}

static void call(void *userdata, GDExtensionClassInstancePtr instance,
                 const GDExtensionConstVariantPtr *args, GDExtensionInt count,
                 GDExtensionVariantPtr result, GDExtensionCallError *error) {
    enum Method method = *(enum Method *)userdata;
    GDExtensionInt expected = method == ACQUIRE ? 1 : 0;
    error->error = GDEXTENSION_CALL_OK;
    if (count != expected) {
        error->error = count < expected ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
        error->expected = (int32_t)expected;
        return;
    }
    if (method == ACQUIRE && variant_type(args[0]) != GDEXTENSION_VARIANT_TYPE_STRING) {
        error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        error->argument = 0;
        error->expected = GDEXTENSION_VARIANT_TYPE_STRING;
        return;
    }
    destroy_variant(result);
    if (method == ACQUIRE) {
        BuiltinString string;
        to_variant_type(GDEXTENSION_VARIANT_TYPE_STRING)(&string, (void *)args[0]);
        int64_t value = lock_path(instance, &string);
        get_destructor(GDEXTENSION_VARIANT_TYPE_STRING)(&string);
        from_variant_type(GDEXTENSION_VARIANT_TYPE_INT)(result, &value);
    } else if (method == RELEASE) {
        unlock(instance);
        nil_variant(result);
    } else {
        GDExtensionBool value = ((Lock *)instance)->handle != INVALID_LOCK;
        from_variant_type(GDEXTENSION_VARIANT_TYPE_BOOL)(result, &value);
    }
}

static void add_method(const char *name, enum Method *id, GDExtensionVariantType return_type) {
    BuiltinString method, argument, empty_name, empty_string = NULL;
    new_name(&method, name, false);
    new_name(&argument, "path", false);
    new_name(&empty_name, "", false);
    GDExtensionPropertyInfo output = {return_type, &empty_name, &empty_name, 0, &empty_string, 6};
    GDExtensionPropertyInfo input = {GDEXTENSION_VARIANT_TYPE_STRING, &argument, &empty_name, 0, &empty_string, 6};
    GDExtensionClassMethodArgumentMetadata metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    GDExtensionClassMethodInfo info = {
        .name = &method, .method_userdata = id, .call_func = call, .ptrcall_func = ptrcall,
        .method_flags = GDEXTENSION_METHOD_FLAG_NORMAL,
        .has_return_value = return_type != GDEXTENSION_VARIANT_TYPE_NIL, .return_value_info = &output,
        .return_value_metadata = return_type == GDEXTENSION_VARIANT_TYPE_INT ? GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64 : metadata,
        .argument_count = *id == ACQUIRE ? 1 : 0, .arguments_info = &input, .arguments_metadata = &metadata
    };
    register_method(library, &class_name, &info);
    GDExtensionPtrDestructor destroy_name = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
    destroy_name(&empty_name);
    destroy_name(&argument);
    destroy_name(&method);
}

static void initialize(void *userdata, GDExtensionInitializationLevel level) {
    (void)userdata;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    new_name(&class_name, "IslandFileLock", false);
    new_name(&parent_name, "RefCounted", false);
    GDExtensionClassCreationInfo6 info = {.is_exposed = true, .create_instance_func = create, .free_instance_func = destroy};
    register_class(library, &class_name, &parent_name, &info);
    add_method("acquire", &acquire_id, GDEXTENSION_VARIANT_TYPE_INT);
    add_method("release", &release_id, GDEXTENSION_VARIANT_TYPE_NIL);
    add_method("is_held", &held_id, GDEXTENSION_VARIANT_TYPE_BOOL);
}

static void deinitialize(void *userdata, GDExtensionInitializationLevel level) {
    (void)userdata;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    unregister_class(library, &class_name);
    GDExtensionPtrDestructor destroy_name = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
    destroy_name(&parent_name);
    destroy_name(&class_name);
}

EXPORT GDExtensionBool island_world_lock_init(GDExtensionInterfaceGetProcAddress resolve,
                                              GDExtensionClassLibraryPtr token,
                                              GDExtensionInitialization *init) {
#define LOAD(target, type, name) target = (type)resolve(name); if (!target) return false
    LOAD(new_name, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");
    LOAD(get_destructor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
    LOAD(from_variant_type, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
    LOAD(to_variant_type, GDExtensionInterfaceGetVariantToTypeConstructor, "get_variant_to_type_constructor");
    LOAD(variant_type, GDExtensionInterfaceVariantGetType, "variant_get_type");
    LOAD(destroy_variant, GDExtensionInterfaceVariantDestroy, "variant_destroy");
    LOAD(nil_variant, GDExtensionInterfaceVariantNewNil, "variant_new_nil");
    LOAD(construct, GDExtensionInterfaceClassdbConstructObject3, "classdb_construct_object3");
    LOAD(set_instance, GDExtensionInterfaceObjectSetInstance, "object_set_instance");
    LOAD(register_class, GDExtensionInterfaceClassdbRegisterExtensionClass6, "classdb_register_extension_class6");
    LOAD(unregister_class, GDExtensionInterfaceClassdbUnregisterExtensionClass, "classdb_unregister_extension_class");
    LOAD(register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
#ifdef _WIN32
    LOAD(path_chars, GDExtensionInterfaceStringToWideChars, "string_to_wide_chars");
#else
    LOAD(path_chars, GDExtensionInterfaceStringToUtf8Chars, "string_to_utf8_chars");
#endif
#undef LOAD
    library = token;
    init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    init->initialize = initialize;
    init->deinitialize = deinitialize;
    return true;
}
