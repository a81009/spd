#!/usr/bin/env python3
"""
Script para executar os testes unitários da API
"""
import sys
import os

# Garantir que o script possa encontrar o módulo api_tests
# independentemente de onde está sendo executado
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

from api_tests import run_tests

if __name__ == "__main__":
    exit_code = run_tests()
    sys.exit(exit_code) 