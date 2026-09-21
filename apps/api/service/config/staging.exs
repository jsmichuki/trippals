import Config

# Staging is a production-like release environment. Runtime values are injected
# by its secret manager; no staging credentials are stored in source control.
import_config "prod.exs"
