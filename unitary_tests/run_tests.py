#!/usr/bin/env python3
"""
Script para executar os testes unitários da API
"""
import sys
from api_tests import run_tests

if __name__ == "__main__":
    exit_code = run_tests()
    sys.exit(exit_code) 