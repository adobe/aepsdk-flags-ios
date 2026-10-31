# Changelog

## Unreleased

### Behavior change
- `Flag.getFeature` now completes with `nil` (and does **not** call `errorCallback`) when a feature is not served to the user: unknown feature key, unmatched targeting, or a feature-group / feature-level control cohort. Previously these cases called `errorCallback` with `AEPError.unexpected`. Apps that treated that error as "feature missing" must handle `nil` in `completion`.
- `errorCallback` is now only called for genuine failures (empty key, missing configuration or client, evaluation failure, error marker, malformed response, dispatch failure or timeout).
- No public signature changes. Exposure reporting is unchanged (control cohorts are still recorded).
