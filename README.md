# Kani packaged for Nix

This nix flake packages the [Kani](https://github.com/model-checking/kani) model checker.

## Installation

```bash
# Install kani and all its dependencies
nix profile install github:fd/nix-kani

# No need to run `kani setup` as it is not necessary under nix.
cargo kani --version
```

## Supported systems

- `x86_64-linux`
- `x86_64-darwin`
- `aarch64-darwin`
