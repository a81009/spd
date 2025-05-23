#!/bin/bash
# Script de verificação de saúde para o autoscaler

# Verifica se o processo do autoscaler está rodando
if pgrep -f "autoscaler" > /dev/null; then
    # Verifica se consegue se conectar ao Prometheus (dependência crítica)
    if wget --spider --quiet "${PROMETHEUS_URL:-http://prometheus:9090}/-/healthy" 2>/dev/null; then
        echo "Autoscaler running and Prometheus accessible"
        exit 0
    else
        echo "Prometheus dependency not accessible"
        exit 1
    fi
else
    echo "Autoscaler process not running"
    exit 1
fi 