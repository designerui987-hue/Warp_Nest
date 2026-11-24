# Test & Verification Strategy

## 1. Testing Philosophy

In accordance with Engineering Principle #1 ("Never fabricate working functionality, benchmark results, or compatibility reports"), every component in WarpNest must be verifiable through automated tests, isolated test fixtures, and reproducible benchmarks.

---

## 2. Testing Pyramid & Test Types

```
               /  Manual Gameplay & Frame-Pacing  \
              /------------------------------------\
             /     End-to-End Store Ingestion       \
            /----------------------------------------\
           /       Graphics Pipeline & Test Scenes    \
          /--------------------------------------------\
         /      Subprocess & Prefix Isolation Tests     \
        /------------------------------------------------\
       /        Unit Tests: Manifest, Fix, DB, Config     \
      +----------------------------------------------------+
```

### 2.1 Unit Tests (Swift Testing & XCTest)
- **Scope**:
  - `WarpLibrary`: Parsing Steam `appmanifest.acf` files, validating JSON responses from Legendary/GOG.
  - `WarpFix`: Validating recipe schema, registry diffing, and environment dictionary generation.
  - `WarpDB`: Testing SQLite migrations, CRUD operations, and recipe query performance.
  - `WarpSense`: Parsing system telemetry data, decoding macOS version strings, and error classification.

### 2.2 Integration & Isolation Tests
- **Scope**:
  - **APFS Clonefile Verification**: Ensure bottle cloning uses copy-on-write and does not duplicate physical disk blocks.
  - **Drive Containment Check**: Verify that `Z:` drive mapping does not expose host root filesystem to the guest environment.
  - **Process Supervision**: Test that killing a simulated game process properly cleans up child `wineserver` instances without leaving zombie processes.

### 2.3 Headless PE Execution Harness (Milestone 1 Benchmark)
- **Scope**:
  - Execute a known, minimal Windows PE executable (e.g. standard console output test binary).
  - Verify return code handling, stdout/stderr capture, and clean termination.
  - Test matrix:
    - 32-bit PE on WoW64.
    - 64-bit PE on 64-bit Wine runtime.

### 2.4 Graphics Validation Suite (Milestone 2)
- **Scope**:
  - Direct3D 11 test scene running through DXMT.
  - Measure frame throughput, GPU memory allocation, and shader cache creation.
  - Automated check for Metal validation layer errors (`MTL_DEBUG_LAYER=1`).

---

## 3. Continuous Verification Harness

A lightweight test runner script will be maintained at `scripts/run_tests.sh`:
- Runs all unit tests via `swift test`.
- Performs static analysis and formatting checks.
- Validates that no forbidden proprietary files (e.g. `D3DMetal.framework`) exist in the workspace.
- Validates all documentation links.
