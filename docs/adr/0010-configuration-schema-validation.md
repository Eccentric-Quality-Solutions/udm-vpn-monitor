# ADR-0010: Configuration Schema Validation

## Status
Accepted

## Context
Configuration files are critical for system operation:
- Invalid configuration can cause script failures
- Type mismatches (string vs integer) can cause unexpected behavior
- Out-of-range values can cause errors
- Missing required values can cause runtime failures
- Default values need to be consistent across the codebase

Without schema validation:
- Configuration errors discovered at runtime
- Inconsistent default values across codebase
- Type errors cause unexpected behavior
- No single source of truth for configuration defaults

## Decision
We will implement a schema-based configuration validation system with:
- Schema definitions for all configuration variables
- Type checking (string, integer, boolean)
- Range validation for numeric values
- Default value application
- Single source of truth for configuration defaults

## Consequences

### Positive
- **Early Error Detection**: Configuration errors caught at startup
- **Type Safety**: Ensures correct types for configuration values
- **Consistent Defaults**: Single source of truth prevents divergence
- **Better Error Messages**: Clear validation errors help users fix configuration
- **Maintainability**: Schema definitions make configuration structure clear

### Negative
- **Initial Setup**: Requires defining schema for all configuration variables
- **Maintenance**: Schema must be kept in sync with code usage
- **Complexity**: Additional validation layer adds complexity

## Implementation Details
- **Schema Module**: `lib/config_schema.sh` defines all configuration variables
- **Schema Format**: Each variable includes:
  - Type (string, integer, boolean)
  - Default value
  - Validation rules (ranges, allowed values)
  - Required/optional flag
- **Configuration Format**: Supports location-based configuration format (`LOCATION_<NAME>_EXTERNAL`/`LOCATION_<NAME>_INTERNAL`)
- **Validation**: `lib/config.sh` validates configuration against schema
- **Default Application**: Defaults applied from schema if values not provided
- **Error Handling**: Invalid values logged with warnings, defaults used
- **Location Parsing**: Location-based configuration parsed separately from standard configuration variables

## Related ADRs
- ADR-0005: Modular Library Architecture
- ADR-0011: Security Measures (IP Validation, Fixed-String Matching)
- ADR-0024: Location-Based Configuration Format

## References
- ARCHITECTURE.md: "Modular Library Architecture" section
- CHANGELOG.md: "Configuration Schema Validation" entry
- lib/config_schema.sh: Schema definitions
- lib/config.sh: Validation implementation

