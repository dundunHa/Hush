## ADDED Requirements

### Requirement: AppKit message cell configuration deduplicates identical render inputs
The system MUST deduplicate repeated `MessageTableCellView.configure` calls when render-relevant inputs are unchanged, to avoid redundant render subscriptions and requests.

#### Scenario: Identical configure input is skipped
- **WHEN** a cell receives a configure call with the same message identity, render generation, streaming state, content fingerprint, and width/style fingerprint as the previous configure call
- **THEN** the cell SHALL skip issuing a new render request
- **AND** SHALL preserve the currently displayed output

#### Scenario: Render-relevant change bypasses deduplication
- **WHEN** any render-relevant input changes (including content fingerprint, streaming flag, render generation, or width/style fingerprint)
- **THEN** the cell SHALL execute the normal configure path
- **AND** SHALL request or apply updated rendering output
