# Mermaid Test

```mermaid
flowchart TD
    A[Start] --> B{Is it working?}
    B -->|Yes| C([Done])
    B -->|No| D[Check deps]
    D --> A
    C --> A
```
