#!/usr/bin/env bash
tar -czf "/backup/pricing-$(date +%F).tgz" /opt/pricing
find /backup -name "*.tgz" -mtime +14 -delete