{ lib
, cmake
, fetchFromGitHub
, git
, llvmPackages
, nixosTests
, overrideCC
, perl
, python3
, stdenv
}:

let
  buildStdenv = overrideCC stdenv llvmPackages.clangUseLLVM;
  opensslArchive =
    let
      # https://github.com/osquery/osquery/blob/877d5e69ab97e15800b5c5128b3de2cf6f322942/libraries/cmake/formula/openssl/CMakeLists.txt#L3-L4.
      version = "1.1.1q";
      sha256 = "d7939ce614029cdff0b6c20f0e2e5703158a489a72b2507b8bd51bf8c8fd10ca";
    in
    builtins.fetchurl {
      inherit sha256;
      url = "https://www.openssl.org/source/openssl-${version}.tar.gz";
    };
in
buildStdenv.mkDerivation rec {
  pname = "osquery";
  version = "5.5.1";

  src = fetchFromGitHub {
    owner = pname;
    repo = pname;
    rev = version;

    fetchSubmodules = true;
    sha256 = "sha256-Q6PQVnBjAjAlR725fyny+RhQFUNwxWGjLDuS5p9JKlU=";
  };

  patches = [
    ./Remove-git-reset.patch
    ./Use-locale.h-instead-of-removed-xlocale.h-header.patch
    ./Remove-circular-definition-of-AUDIT_FILTER_EXCLUDE.patch
    # For current state of compilation against glibc in the clangWithLLVM toolchain, refer to the upstream issue in https://github.com/osquery/osquery/issues/7823.
    ./Remove-system-controls-table.patch
  ];


  buildInputs = [
    llvmPackages.libunwind
  ];
  nativeBuildInputs = [
    cmake
    git
    perl
    python3
  ];

  postPatch = ''
    substituteInPlace cmake/install_directives.cmake --replace "/control" "control"
  '';

  # For explanation of these deletions, refer to the ./Use-locale.h-instead-of-removed-xlocale.h-header.patch file.
  preConfigure = ''
    find libraries/cmake/source -name 'config.h' -exec sed -i '/#define HAVE_XLOCALE_H 1/d' {} \;
  '';

  cmakeFlags = [
    "-DOSQUERY_VERSION=${version}"
    "-DOSQUERY_OPENSSL_ARCHIVE_PATH=${opensslArchive}"
  ];

  postFixup = ''
    patchelf --set-rpath "${lib.makeLibraryPath buildInputs}:$(patchelf --print-rpath $out/bin/osqueryd)" "$out/bin/osqueryd"
  '';

  meta = with lib; {
    description = "SQL powered operating system instrumentation, monitoring, and analytics.";
    longDescription = ''
      The system controls table is not included as it does not presently compile with glibc >= 2.32. For more information, refer to https://github.com/osquery/osquery/issues/7823
    '';
    homepage = "https://osquery.io";
    license = licenses.bsd3;
    platforms = platforms.linux;
    maintainers = with maintainers; [ jdbaldry znewman01 ];
  };
}
