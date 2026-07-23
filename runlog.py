import csv
import os
from datetime import datetime

LOG_FILE = "runlog.csv"

def log_run(spec_file, mode, writer_model, improver_model,
            reviewer_model, n_vars, output_file):
    """Append one line recording this generation run."""
    is_new = not os.path.exists(LOG_FILE)

    with open(LOG_FILE, "a", newline="") as f:
        writer = csv.writer(f)
        if is_new:
            writer.writerow(["timestamp", "spec_file", "mode",
                             "writer_model", "improver_model",
                             "reviewer_model", "variables_generated",
                             "output_file"])
        writer.writerow([
            datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            spec_file,
            mode,
            writer_model,
            improver_model,
            reviewer_model,
            n_vars,
            output_file,
        ])