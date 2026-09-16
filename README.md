# ⚙️ Pipeline ETL e Distribuição de SLAs no Azure Databricks

Este repositório contém os scripts de um pipeline de dados construído para rodar em ambiente **Azure Databricks**. O objetivo principal desta arquitetura é orquestrar, classificar e distribuir fluxos de trabalho operacionais, garantindo o cumprimento de SLAs regulatórios e de negócios.

## 🏗️ Arquitetura e Tecnologias
* **Ambiente:** Azure Databricks
* **Linguagens:** Python (PySpark) e SQL Avançado
* **Otimização:** Uso de recursos Delta Lake (MERGE, OPTIMIZE) e refatoração de Joins.

## 📁 Estrutura dos Arquivos

1. **`00_orquestrador_pipeline.py`**: Notebook mestre em Python (PySpark) que simula a orquestração via Databricks Jobs, executando os notebooks SQL na sequência correta de dependência.
2. **`01_ancoragem_workflow.sql`**: Script responsável por identificar analistas ativos/pausados e fazer a ancoragem inicial da carga de trabalho.
3. **`02_view_refino.sql`**: Aplica regras de negócio específicas (como direcionamento de fluxos focais) e valida a necessidade de redistribuição de demandas.
4. **`03_classificacao.sql`**: Consolida os dados com tabelas de domínio, calcula o tempo de SLA excluindo finais de semana e feriados (dias úteis) e finaliza atualizando a tabela Delta alvo, rodando o comando `OPTIMIZE` para performance de leitura.

## 🚀 Destaques Técnicos
* **Performance:** Substituição de `OR-JOINs` complexos por `UNION` para habilitar *Hash Joins* nativos da engine do Spark, reduzindo o tempo de processamento.
* **Redução de Scans:** Refatoração de múltiplas CTEs para um *scan* único nas tabelas de histórico maiores.
