FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN chmod +x healthcheck.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD ["./healthcheck.sh"]

CMD ["python", "autoscaler.py"] 