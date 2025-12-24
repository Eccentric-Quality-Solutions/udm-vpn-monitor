# ADR-0007: Comprehensive In-Code Documentation

## Status
Accepted

## Context
The codebase needs to be maintainable and understandable by:
- Original developers
- New contributors
- System administrators troubleshooting issues
- Future maintainers

Without comprehensive documentation:
- Function purposes and behaviors are unclear
- Parameter types and requirements are ambiguous
- Side effects (file operations, logging) are not obvious
- Usage examples are missing
- Dependencies between functions are unclear

## Decision
We will include comprehensive documentation blocks for all functions with:
- Function purpose and behavior description
- Parameter descriptions with types
- Return value documentation
- Side effects documentation (file operations, logging, etc.)
- Usage examples for complex functions
- Notes about dependencies and requirements

## Consequences

### Positive
- **Easier Onboarding**: New developers can understand code quickly
- **Better Code Understanding**: Clear documentation of function behavior
- **Reduced Need for External Docs**: Documentation lives with code
- **Self-Documenting Code**: Functions explain themselves
- **Better Maintenance**: Easier to modify code when behavior is documented

### Negative
- **Maintenance Overhead**: Documentation must be kept up-to-date with code changes
- **Code Length**: Documentation adds lines to source files (but improves readability)

## Implementation Details
- **Documentation Format**: Bash comment blocks before each function
- **Required Sections**:
  - Purpose/Description
  - Arguments (with types)
  - Returns (exit codes, return values)
  - Side Effects (file operations, logging, state changes)
  - Examples (for complex functions)
  - Notes (dependencies, requirements, warnings)
- **Consistency**: All functions follow the same documentation format
- **Examples**: Complex functions include usage examples

## Related ADRs
- ADR-0005: Modular Library Architecture

## References
- ARCHITECTURE.md: "Key Design Decisions #7: Comprehensive In-Code Documentation"
- User rules: "When adding or updating code you should create or update the code documentation that goes along with it"
- All lib/*.sh files: Examples of comprehensive function documentation

