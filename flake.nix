{
  description = "PageIndex - A vectorless, reasoning-based RAG system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # System-independent overlay: adds pageindex to all pythonPackages sets
      overlay = final: prev: {
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (python-final: python-prev: {
            pageindex = python-final.buildPythonPackage {
              pname = "pageindex";
              version = "0.1.0";
              pyproject = true;

              src = final.lib.fileset.toSource {
                root = ./.;
                fileset = final.lib.fileset.unions [
                  ./pyproject.toml
                  ./pageindex
                  ./run_pageindex.py
                  ./README.md
                ];
              };

              build-system = [
                python-final.setuptools
                python-final.wheel
              ];

              dependencies = [
                python-final.openai
                python-final.pymupdf
                python-final.pypdf2
                python-final."python-dotenv"
                python-final.tiktoken
                python-final.pyyaml
              ];

              pythonImportsCheck = [ "pageindex" ];

              meta = {
                description = "A vectorless, reasoning-based RAG system";
                homepage = "https://github.com/VectifyAI/PageIndex";
                license = final.lib.licenses.mit;
              };
            };
          })
        ];
      };

      # Shell snippet that finds the best CA bundle including private CAs.
      # User-managed bundles are checked first since system/nix bundles often
      # contain only Mozilla CAs and lack private CA certificates.
      sslSetup = ''
        _find_ca_bundle() {
          for _ca in "$HOME/.config/curl/ca-bundle.crt" \
                     "$HOME/.local/share/ca-certificates/ca-bundle.crt" \
                     "''${NIX_SSL_CERT_FILE:-}"; do
            if [ -n "$_ca" ] && [ -f "$_ca" ]; then
              echo "$_ca"
              return
            fi
          done
        }
        _bundle=$(_find_ca_bundle)
        if [ -n "$_bundle" ]; then
          export SSL_CERT_FILE="$_bundle"
        fi
        unset -f _find_ca_bundle
        unset _bundle
      '';
    in
    { overlays.default = overlay; }
    //
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ overlay ];
        };

        python = pkgs.python3;

        pythonEnv = python.withPackages (ps: [ ps.pageindex ]);

        devPythonEnv = python.withPackages (ps: [
          ps.pageindex
          ps.ipython
          ps.pytest
        ]);
      in
      {
        packages = {
          default = python.pkgs.pageindex;
          pageindex = python.pkgs.pageindex;
        };

        apps.default = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "pageindex" ''
            ${sslSetup}
            exec ${pythonEnv}/bin/python ${self}/run_pageindex.py "$@"
          ''}/bin/pageindex";
        };

        devShells.default = pkgs.mkShell {
          packages = [ devPythonEnv ];

          shellHook = ''
            ${sslSetup}
            echo "PageIndex development environment"
            echo "Python: $(python --version)"
            echo ""
            echo "Commands:"
            echo "  python run_pageindex.py --pdf_path <file>  Run PageIndex"
            echo "  ipython                                    Interactive shell"
            echo "  pytest                                     Run tests"
          '';
        };
      }
    );
}
