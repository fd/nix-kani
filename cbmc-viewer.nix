{ pkgs
, fetchFromGitHub
, cbmcViewerPython ? pkgs.python311
}:
let
  pname = "cbmc-viewer";
  version = "3.8";
  hash = "sha256-GIpinwjl/v6Dz5HyOsoPfM9fxG0poZ0HPsKLe9js9vM=";
in
cbmcViewerPython.pkgs.buildPythonPackage {
  inherit pname version;
  format = "pyproject";

  propagatedBuildInputs = [
    pkgs.cbmc
    pkgs.universal-ctags
    cbmcViewerPython.pkgs.jinja2
    cbmcViewerPython.pkgs.setuptools
    cbmcViewerPython.pkgs.voluptuous
  ];

  src = fetchFromGitHub {
    pname = "${pname}-source";
    inherit version hash;

    owner = "model-checking";
    repo = "cbmc-viewer";

    rev = "viewer-${version}";
  };
}
