#!/usr/bin/env python3
"""Write a no-op firebase-cpp-sdk tree for YabaSanshiro Qt builds."""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <firebase-cpp-sdk-dest>", file=sys.stderr)
        return 2
    dest = Path(sys.argv[1])
    if dest.exists():
        import shutil

        shutil.rmtree(dest)
    (dest / "src").mkdir(parents=True)
    (dest / "include/firebase").mkdir(parents=True)

    (dest / "CMakeLists.txt").write_text(
        """cmake_minimum_required(VERSION 3.16)
project(firebase-cpp-sdk-stub LANGUAGES CXX)
add_library(firebase_stub STATIC src/stub.cpp)
target_include_directories(firebase_stub PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_compile_features(firebase_stub PUBLIC cxx_std_14)
foreach(t firebase_app firebase_auth firebase_storage firebase_database firebase_firestore)
  add_library(${t} ALIAS firebase_stub)
endforeach()
"""
    )
    (dest / "src/stub.cpp").write_text(
        "// MasiScript Firebase stub\n"
        "namespace firebase { namespace stub { int keep_alive = 0; } }\n"
    )

    inc = dest / "include/firebase"
    files: dict[str, str] = {
        "future.h": """#pragma once
#include <functional>
#include <type_traits>
namespace firebase {
enum FutureStatus { kFutureStatusComplete = 0, kFutureStatusPending = 1, kFutureStatusInvalid = 2 };
template <typename T>
class Future {
 public:
  FutureStatus status() const { return kFutureStatusComplete; }
  int error() const { return 0; }
  const char* error_message() const { return ""; }
  const T* result() const { return &value_; }
  void OnCompletion(void (*cb)(const Future<T>&, void*), void* data) const { if (cb) cb(*this, data); }
  template <typename F> void OnCompletion(F&& cb) const { cb(*this); }
 private:
  typename std::conditional<std::is_void<T>::value, char, T>::type value_{};
};
template <>
class Future<void> {
 public:
  FutureStatus status() const { return kFutureStatusComplete; }
  int error() const { return 0; }
  const char* error_message() const { return ""; }
  const void* result() const { return nullptr; }
  void OnCompletion(void (*cb)(const Future<void>&, void*), void* data) const { if (cb) cb(*this, data); }
  template <typename F> void OnCompletion(F&& cb) const { cb(*this); }
};
}  // namespace firebase
""",
        "app.h": """#pragma once
#include <string>
namespace firebase {
class AppOptions {
 public:
  void set_api_key(const char*) {}
  void set_app_id(const char*) {}
  void set_database_url(const char*) {}
  void set_storage_bucket(const char*) {}
  void set_project_id(const char*) {}
  void set_messaging_sender_id(const char*) {}
};
class App {
 public:
  static App* Create(const AppOptions& = AppOptions()) { static App app; return &app; }
  static App* GetInstance() { return Create(); }
};
}  // namespace firebase
""",
        "variant.h": """#pragma once
#include <cstdint>
#include <map>
#include <string>
namespace firebase {
class Timestamp {
 public:
  Timestamp() = default;
  static Timestamp Now() { return {}; }
  int64_t seconds() const { return 0; }
  int32_t nanoseconds() const { return 0; }
};
class Variant {
 public:
  Variant() = default;
  Variant(bool) {}
  Variant(int) {}
  Variant(int64_t) {}
  Variant(double) {}
  Variant(const char*) {}
  Variant(const std::string&) {}
  bool is_null() const { return true; }
  bool is_map() const { return false; }
  bool is_string() const { return false; }
  bool is_int64() const { return false; }
  bool is_integer() const { return false; }
  bool is_bool() const { return false; }
  bool is_double() const { return false; }
  bool is_timestamp() const { return false; }
  int64_t int64_value() const { return 0; }
  int64_t integer_value() const { return 0; }
  bool bool_value() const { return false; }
  double double_value() const { return 0; }
  const char* string_value() const { return ""; }
  Timestamp timestamp_value() const { return {}; }
  const std::map<Variant, Variant>& map() const { static std::map<Variant, Variant> m; return m; }
  bool operator<(const Variant&) const { return false; }
};
}  // namespace firebase
""",
        "auth.h": """#pragma once
#include "firebase/app.h"
#include "firebase/future.h"
#include <string>
namespace firebase {
namespace auth {
enum AuthError { kAuthErrorNone = 0 };
class User {
 public:
  bool is_valid() const { return false; }
  std::string uid() const { return {}; }
  std::string DisplayName() const { return {}; }
  std::string display_name() const { return {}; }
  std::string email() const { return {}; }
  std::string photo_url() const { return {}; }
};
class Credential {};
class GoogleAuthProvider {
 public:
  static Credential GetCredential(const char*, const char*) { return {}; }
};
class AuthStateListener {
 public:
  virtual ~AuthStateListener() = default;
  virtual void OnAuthStateChanged(class Auth*) = 0;
};
class Auth {
 public:
  static Auth* GetAuth(App*) { static Auth auth; return &auth; }
  User current_user() { return {}; }
  void AddAuthStateListener(AuthStateListener*) {}
  void RemoveAuthStateListener(AuthStateListener*) {}
  Future<User> SignInWithCredential(const Credential&) { return {}; }
  void SignOut() {}
};
}  // namespace auth
}  // namespace firebase
""",
        "database.h": """#pragma once
#include "firebase/app.h"
#include "firebase/future.h"
#include "firebase/variant.h"
#include <map>
#include <string>
#include <vector>
namespace firebase {
namespace database {
enum Error { kErrorNone = 0 };
enum TransactionResult { kTransactionResultSuccess = 0, kTransactionResultAbort = 1 };
class MutableData {
 public:
  Variant value() const { return {}; }
  void set_value(const Variant&) {}
};
class DataSnapshot {
 public:
  bool exists() const { return false; }
  bool is_valid() const { return false; }
  Variant value() const { return {}; }
  std::string key() const { return {}; }
  DataSnapshot Child(const std::string&) const { return {}; }
  DataSnapshot Child(const char*) const { return {}; }
  std::vector<DataSnapshot> children() const { return {}; }
};
class ValueListener {
 public:
  virtual ~ValueListener() = default;
  virtual void OnValueChanged(const DataSnapshot&) = 0;
  virtual void OnCancelled(const Error&, const char*) = 0;
};
class DatabaseReference {
 public:
  DatabaseReference Child(const std::string&) const { return {}; }
  DatabaseReference Child(const char*) const { return {}; }
  DatabaseReference PushChild() const { return {}; }
  std::string key() const { return {}; }
  void AddValueListener(ValueListener*) {}
  void RemoveValueListener(ValueListener*) {}
  Future<void> SetValue(const Variant&) { return {}; }
  Future<void> RemoveValue() { return {}; }
  Future<void> UpdateChildren(const std::map<std::string, Variant>&) { return {}; }
  Future<DataSnapshot> GetValue() { return {}; }
  template <typename F>
  Future<void> RunTransaction(F&&) { return {}; }
};
class Database {
 public:
  static Database* GetInstance(App*) { static Database db; return &db; }
  DatabaseReference GetReference() { return {}; }
  DatabaseReference GetReference(const char*) { return {}; }
};
}  // namespace database
}  // namespace firebase
""",
        "storage.h": """#pragma once
#include "firebase/app.h"
#include "firebase/future.h"
#include <cstddef>
#include <cstdint>
#include <map>
#include <string>
#include <vector>
namespace firebase {
namespace storage {
enum Error { kErrorNone = 0 };
class Metadata {
 public:
  int64_t size_bytes() const { return 0; }
  std::string path() const { return {}; }
  std::string name() const { return {}; }
  void set_content_type(const char*) {}
  std::map<std::string, std::string>* custom_metadata() {
    static std::map<std::string, std::string> m; return &m;
  }
};
class Controller {};
class Listener {
 public:
  virtual ~Listener() = default;
};
class StorageReference {
 public:
  StorageReference() = default;
  StorageReference Child(const std::string&) const { return {}; }
  StorageReference Child(const char*) const { return {}; }
  std::string bucket() const { return {}; }
  Future<Metadata> GetMetadata() { return {}; }
  Future<size_t> GetFile(const char*) { return {}; }
  Future<Metadata> PutFile(const char*) { return {}; }
  Future<Metadata> PutBytes(const void*, size_t, const Metadata& = Metadata(),
                            Listener* = nullptr, Controller* = nullptr) { return {}; }
  Future<void> Delete() { return {}; }
  Future<std::string> GetDownloadUrl() { return {}; }
};
class Storage {
 public:
  static Storage* GetInstance(App*, const char* = nullptr) { static Storage s; return &s; }
  StorageReference GetReference() { return {}; }
  StorageReference GetReferenceFromUrl(const char*) { return {}; }
};
}  // namespace storage
}  // namespace firebase
""",
        "storage/metadata.h": '#pragma once\n#include "firebase/storage.h"\n',
        "firestore/document_snapshot.h": """#pragma once
#include "firebase/variant.h"
#include <cstdint>
#include <map>
#include <string>
namespace firebase {
namespace firestore {
class DocumentReference;
class FieldValue {
 public:
  static FieldValue Null() { return {}; }
  static FieldValue Integer(int64_t) { return {}; }
  static FieldValue Boolean(bool) { return {}; }
  static FieldValue String(const std::string&) { return {}; }
  static FieldValue Timestamp(const ::firebase::Timestamp&) { return {}; }
  bool is_null() const { return true; }
  bool is_integer() const { return false; }
  bool is_string() const { return false; }
  bool is_timestamp() const { return false; }
  bool is_map() const { return false; }
  bool is_boolean() const { return false; }
  int64_t integer_value() const { return 0; }
  bool boolean_value() const { return false; }
  std::string string_value() const { return {}; }
  ::firebase::Timestamp timestamp_value() const { return {}; }
  const std::map<std::string, FieldValue>& map_value() const {
    static std::map<std::string, FieldValue> m; return m;
  }
};
using MapFieldValue = std::map<std::string, FieldValue>;
class DocumentSnapshot {
 public:
  bool exists() const { return false; }
  std::string id() const { return {}; }
  MapFieldValue GetData() const { return {}; }
  DocumentReference reference() const;
};
}  // namespace firestore
}  // namespace firebase
""",
        "firestore/query_snapshot.h": """#pragma once
#include "firebase/firestore/document_snapshot.h"
#include <vector>
namespace firebase {
namespace firestore {
class QuerySnapshot {
 public:
  const std::vector<DocumentSnapshot>& documents() const {
    static std::vector<DocumentSnapshot> v; return v;
  }
  std::size_t size() const { return 0; }
};
}  // namespace firestore
}  // namespace firebase
""",
        "firestore.h": """#pragma once
#include "firebase/app.h"
#include "firebase/future.h"
#include "firebase/variant.h"
#include "firebase/firestore/document_snapshot.h"
#include "firebase/firestore/query_snapshot.h"
#include <string>
namespace firebase {
namespace firestore {
class CollectionReference;
class DocumentReference {
 public:
  CollectionReference Collection(const std::string&) const;
  Future<DocumentSnapshot> Get() const { return {}; }
  std::string path() const { return {}; }
};
class Query {
 public:
  enum class Direction { kAscending = 0, kDescending = 1 };
  Query WhereEqualTo(const std::string&, const FieldValue&) const { return {}; }
  Query OrderBy(const std::string&, Direction = Direction::kAscending) const { return {}; }
  Query Limit(int) const { return {}; }
  Future<QuerySnapshot> Get() const { return {}; }
};
class CollectionReference : public Query {
 public:
  DocumentReference Document(const std::string&) const { return {}; }
};
inline CollectionReference DocumentReference::Collection(const std::string&) const { return {}; }
inline DocumentReference DocumentSnapshot::reference() const { return {}; }
class Firestore {
 public:
  static Firestore* GetInstance(App*) { static Firestore fs; return &fs; }
  CollectionReference Collection(const std::string&) const { return {}; }
  CollectionReference Collection(const char* p) const { return Collection(std::string(p ? p : "")); }
  DocumentReference Document(const std::string&) const { return {}; }
};
}  // namespace firestore
}  // namespace firebase
""",
        "auth/user.h": '#pragma once\n#include "firebase/auth.h"\n',
        "database/database_reference.h": '#pragma once\n#include "firebase/database.h"\n',
        "storage/storage_reference.h": '#pragma once\n#include "firebase/storage.h"\n',
    }

    for rel, body in files.items():
        path = inc / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body)
    print(f"wrote {len(files)} firebase stub headers under {dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
