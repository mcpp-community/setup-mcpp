# setup-mcpp

A GitHub Action that installs [mcpp](https://github.com/mcpp-community/mcpp), the C++23 modules build tool,
on Linux, macOS and Windows runners. mcpp is installed through [xlings](https://github.com/openxlings/xlings)
and placed on `PATH`.

```yaml
- uses: mcpp-community/setup-mcpp@v1
- run: mcpp build && mcpp test
```

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `version` | `latest` | mcpp release, such as `2026.11.16.1` |
| `xlings-version` | `latest` | xlings release that installs mcpp |
| `mirror` | `GLOBAL` | package mirror, `GLOBAL` or `CN` |
| `toolchains` | | toolchains to install; each line is one `mcpp toolchain install` argument list |
| `cache` | `false` | keep `~/.xlings` and `~/.mcpp` in the Actions cache |

The cache key names the operating system, the architecture, both releases, the toolchain list and the hash
of `mcpp.lock`.

## Outputs

| Output | Meaning |
|---|---|
| `version` | the installed mcpp release |
| `cache-hit` | `true` when the cache was restored by its exact key |

## Example

```yaml
jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-24.04, ubuntu-24.04-arm, macos-15, windows-2022]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: mcpp-community/setup-mcpp@v1
        with:
          version: 2026.11.16.1
          cache: true
          toolchains: |
            llvm
      - run: mcpp build --release
```

## License

Apache-2.0
