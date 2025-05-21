#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Iniciando sistemas distribuídos..."
docker compose up --build -d

echo "⏳ Aguardando serviços iniciarem..."
sleep 10  # Aguarda inicialização mínima

echo "🧪 Executando testes unitários..."
# Instala as dependências necessárias se não existirem
which pip > /dev/null || { echo "Instalando pip..."; apt-get update && apt-get install -y python3-pip; }
pip install requests > /dev/null 2>&1 || echo "Dependências já instaladas"

# Executa os testes unitários
python3 tests.py

# Se os testes passarem (código de saída 0), continua com a inicialização
if [ $? -eq 0 ]; then
    echo
    echo "✅ Testes concluídos com sucesso! Sistema pronto para uso."
    echo
    echo "🌐 Nginx LB → http://localhost/"
    echo "🐇 RabbitMQ UI → http://localhost:25673 (admin/admin)"
    echo "🐓 Cockroach UI → http://localhost:8080"
    echo "📘 Swagger → http://localhost/docs"
    echo "📊 Prometheus → http://localhost:9091"
    echo "📈 Grafana → http://localhost:3000 (admin/admin)"
    echo "🔍 Health API → http://localhost/health"
    echo
    echo "Sistema iniciado e em execução! 🚀"
else
    echo "❌ Testes unitários falharam! Verifique os logs para mais detalhes."
    echo "ℹ️ O sistema está rodando, mas pode não estar funcionando corretamente."
fi
