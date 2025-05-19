# consumer/Dockerfile
FROM python:3.12-slim

WORKDIR /app

# dependências - só as que o worker usa
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# cópia do código
COPY . .

# Expor portas para métricas e health check
EXPOSE 9090
EXPOSE 8080

CMD ["python", "-m", "worker"]
