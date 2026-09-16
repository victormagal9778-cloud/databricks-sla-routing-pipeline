# Databricks notebook source
# ==============================================================================
# Orquestrador do Pipeline de Classificação e Distribuição de Workflows
# ==============================================================================

# Definição de parâmetros para execução em Jobs/Workflows
dbutils.widgets.text("ambiente", "prd", "Ambiente de Execução")
ambiente = dbutils.widgets.get("ambiente")

print(f"Iniciando orquestração do pipeline no ambiente: {ambiente.upper()}")

try:
    # Passo 1: Executa a ancoragem e identifica analistas ativos/pausados
    print("-> [1/3] Executando Ancoragem de Workflows...")
    dbutils.notebook.run("./01_ancoragem_workflow", 1200)

    # Passo 2: Aplica regras de negócio específicas (Focal/Redistribuir)
    print("-> [2/3] Executando Refino de Regras e Direcionamento...")
    dbutils.notebook.run("./02_view_refino", 1200)

    # Passo 3: Consolida dados, calcula SLA por dias úteis e roda o OPTIMIZE
    print("-> [3/3] Executando Classificação de Consumo e SLA...")
    dbutils.notebook.run("./03_classificacao", 1800)

    print("✅ Pipeline executado e tabelas Delta atualizadas com sucesso!")

except Exception as e:
    print(f"❌ Falha na execução do pipeline: {str(e)}")
    raise e