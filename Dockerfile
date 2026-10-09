FROM python:3.12-slim AS base

# Patch OS-level packages at build time, so the image doesn't ship whatever
# CVEs happened to exist in the base layer on the day it was published
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Run as non-root — a thing reviewers and image scanners both check for
RUN addgroup --system app && adduser --system --ingroup app app

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

COPY app.py .
USER app

EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]