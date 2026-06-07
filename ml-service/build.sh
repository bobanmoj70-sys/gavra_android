#!/bin/bash
# Build skripta za Render.com
# Trenira ML model prilikom deploy-a

echo "Training ML model before deploy..."
python training/train.py
