FROM python:3.12-slim

# 1. dependências básicas
WORKDIR /app
COPY app/ app/
COPY app/requirements.txt .
COPY index.html /app/index.html
RUN pip install --no-cache-dir -r requirements.txt

# 2. expõe a porta
EXPOSE 8000

# 3. comando de arranque
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
