# Container flaw 1: outdated base image with known CVEs
FROM python:3.8

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Container flaw 2: running as root inside the container
USER root

EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]