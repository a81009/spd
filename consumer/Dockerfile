# consumer/Dockerfile
FROM python:3.12-slim

WORKDIR /app

# dependências - só as que o worker usa
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# cópia do código
COPY worker.py .

CMD ["python", "worker.py"]
