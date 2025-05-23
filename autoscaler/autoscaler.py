#!/usr/bin/env python3
"""
Auto-scaler para o sistema distribuído key-value
Baseado em métricas de CPU e memória do Prometheus
"""

import os
import time
import logging
import sys
import docker
import requests
import schedule
from dotenv import load_dotenv

# Configuração do logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)

# Carregar variáveis de ambiente
load_dotenv()

# Configurações do Prometheus
PROMETHEUS_URL = os.environ.get('PROMETHEUS_URL', 'http://prometheus:9090')

# Configurações para o serviço API
API_REPLICAS_MIN = int(os.environ.get('API_REPLICAS_MIN', 2))
API_REPLICAS_MAX = int(os.environ.get('API_REPLICAS_MAX', 10))
API_CPU_HIGH = float(os.environ.get('API_CPU_HIGH_THRESHOLD', 70))
API_CPU_LOW = float(os.environ.get('API_CPU_LOW_THRESHOLD', 30))
API_MEMORY_HIGH = float(os.environ.get('API_MEMORY_HIGH_THRESHOLD', 80))
API_MEMORY_LOW = float(os.environ.get('API_MEMORY_LOW_THRESHOLD', 40))

# Configurações para o serviço Consumer
CONSUMER_REPLICAS_MIN = int(os.environ.get('CONSUMER_REPLICAS_MIN', 2))
CONSUMER_REPLICAS_MAX = int(os.environ.get('CONSUMER_REPLICAS_MAX', 8))
CONSUMER_CPU_HIGH = float(os.environ.get('CONSUMER_CPU_HIGH_THRESHOLD', 70))
CONSUMER_CPU_LOW = float(os.environ.get('CONSUMER_CPU_LOW_THRESHOLD', 30))
CONSUMER_MEMORY_HIGH = float(os.environ.get('CONSUMER_MEMORY_HIGH_THRESHOLD', 80))
CONSUMER_MEMORY_LOW = float(os.environ.get('CONSUMER_MEMORY_LOW_THRESHOLD', 40))

# Intervalo de verificação em segundos
SCALING_INTERVAL = int(os.environ.get('SCALING_INTERVAL', 30))

# Nomes dos serviços
API_SERVICE = 'api'
CONSUMER_SERVICE = 'consumer'

# Cliente Docker
client = docker.from_env()

def get_metric(service, metric_type):
    """
    Obter métrica do Prometheus para um serviço específico
    metric_type: 'cpu' ou 'memory'
    """
    try:
        if metric_type == 'cpu':
            # CPU utilization em porcentagem (0-100)
            query = f'avg(rate(process_cpu_seconds_total{{job="{service}"}}[1m]) * 100)'
        elif metric_type == 'memory':
            # Memory utilization em porcentagem da memória total
            query = f'avg(process_resident_memory_bytes{{job="{service}"}} / container_memory_limit_bytes{{job="{service}"}} * 100)'
        else:
            logging.error(f"Tipo de métrica desconhecido: {metric_type}")
            return 0

        response = requests.get(
            f'{PROMETHEUS_URL}/api/v1/query',
            params={'query': query}
        )
        
        if response.status_code != 200:
            logging.error(f"Erro ao consultar Prometheus: {response.status_code} - {response.text}")
            return 0
            
        result = response.json()
        if result['status'] == 'success' and result['data']['result']:
            value = float(result['data']['result'][0]['value'][1])
            logging.info(f"Métrica {metric_type} para {service}: {value:.2f}%")
            return value
        else:
            logging.warning(f"Nenhum resultado para a métrica {metric_type} do serviço {service}")
            return 0
            
    except Exception as e:
        logging.error(f"Erro ao obter métrica {metric_type} para {service}: {e}")
        return 0

def scale_service(service_name, replicas):
    """
    Escalar um serviço para o número especificado de réplicas
    """
    try:
        # Obter o serviço
        services = client.services.list(filters={'name': service_name})
        if not services:
            logging.error(f"Serviço {service_name} não encontrado")
            return False
        
        service = services[0]
        
        # Obter a configuração atual
        current_spec = service.attrs['Spec']
        if 'Mode' in current_spec and 'Replicated' in current_spec['Mode']:
            current_replicas = current_spec['Mode']['Replicated']['Replicas']
            if current_replicas == replicas:
                logging.info(f"Serviço {service_name} já está com {replicas} réplicas")
                return True
                
            # Atualizar o número de réplicas
            current_spec['Mode']['Replicated']['Replicas'] = replicas
            service.update(current_spec)
            logging.info(f"Serviço {service_name} escalado de {current_replicas} para {replicas} réplicas")
            return True
        else:
            logging.error(f"Serviço {service_name} não está em modo replicado")
            return False
            
    except Exception as e:
        logging.error(f"Erro ao escalar serviço {service_name}: {e}")
        return False

def check_and_scale(service, min_replicas, max_replicas, cpu_high, cpu_low, memory_high, memory_low):
    """
    Verificar métricas e escalar serviço se necessário
    """
    logging.info(f"Verificando métricas para {service}...")
    
    # Obter métricas atuais
    cpu_usage = get_metric(service, 'cpu')
    memory_usage = get_metric(service, 'memory')
    
    # Obter número atual de réplicas
    try:
        services = client.services.list(filters={'name': service})
        if not services:
            logging.error(f"Serviço {service} não encontrado")
            return
            
        current_spec = services[0].attrs['Spec']
        if 'Mode' in current_spec and 'Replicated' in current_spec['Mode']:
            current_replicas = current_spec['Mode']['Replicated']['Replicas']
        else:
            logging.error(f"Serviço {service} não está em modo replicado")
            return
    except Exception as e:
        logging.error(f"Erro ao obter réplicas atuais para {service}: {e}")
        return
    
    # Lógica de escala
    if cpu_usage > cpu_high or memory_usage > memory_high:
        if current_replicas < max_replicas:
            new_replicas = min(current_replicas + 1, max_replicas)
            logging.info(f"Escalando UP {service} por alto uso (CPU: {cpu_usage:.1f}%, MEM: {memory_usage:.1f}%)")
            scale_service(service, new_replicas)
        else:
            logging.info(f"Serviço {service} já está no máximo de réplicas ({max_replicas})")
    elif cpu_usage < cpu_low and memory_usage < memory_low:
        if current_replicas > min_replicas:
            new_replicas = max(current_replicas - 1, min_replicas)
            logging.info(f"Escalando DOWN {service} por baixo uso (CPU: {cpu_usage:.1f}%, MEM: {memory_usage:.1f}%)")
            scale_service(service, new_replicas)
        else:
            logging.info(f"Serviço {service} já está no mínimo de réplicas ({min_replicas})")
    else:
        logging.info(f"Não é necessário escalar {service} (CPU: {cpu_usage:.1f}%, MEM: {memory_usage:.1f}%)")

def check_api():
    """Verificar e escalar o serviço API"""
    check_and_scale(
        API_SERVICE, 
        API_REPLICAS_MIN, 
        API_REPLICAS_MAX, 
        API_CPU_HIGH, 
        API_CPU_LOW, 
        API_MEMORY_HIGH, 
        API_MEMORY_LOW
    )

def check_consumer():
    """Verificar e escalar o serviço Consumer"""
    check_and_scale(
        CONSUMER_SERVICE, 
        CONSUMER_REPLICAS_MIN, 
        CONSUMER_REPLICAS_MAX, 
        CONSUMER_CPU_HIGH, 
        CONSUMER_CPU_LOW, 
        CONSUMER_MEMORY_HIGH, 
        CONSUMER_MEMORY_LOW
    )

def main():
    """Função principal"""
    logging.info("Iniciando auto-scaler")
    
    # Verificar conexão com o Prometheus
    try:
        response = requests.get(f'{PROMETHEUS_URL}/-/ready')
        if response.status_code != 200:
            logging.error(f"Prometheus não está pronto: {response.status_code}")
        else:
            logging.info("Conexão com Prometheus estabelecida")
    except Exception as e:
        logging.error(f"Erro ao conectar com Prometheus: {e}")
    
    # Agendar verificações periódicas
    schedule.every(SCALING_INTERVAL).seconds.do(check_api)
    schedule.every(SCALING_INTERVAL).seconds.do(check_consumer)
    
    # Executar a primeira verificação imediatamente
    check_api()
    check_consumer()
    
    # Loop principal
    while True:
        schedule.run_pending()
        time.sleep(1)

if __name__ == "__main__":
    main() 