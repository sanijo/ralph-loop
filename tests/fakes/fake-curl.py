#!/usr/bin/env python3
"""Record a notification request instead of sending it; fail on request."""

import os
import sys

from support import record

record("curl")
# A non-zero status models an unreachable or rejecting notification API.
sys.exit(int(os.environ.get("RALPH_TEST_CURL_STATUS", "0")))
