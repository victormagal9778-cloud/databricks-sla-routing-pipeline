from datetime import datetime, time, timedelta
import base64
import io
import json
import time as _time
import uuid
from urllib.parse import quote

import requests
from pyspark.sql import functions as F

try:
    from zoneinfo import ZoneInfo
    TZ = ZoneInfo("America/Sao_Paulo")
except Exception:
    TZ = None

# --------------------------------------------------------------------
# CONFIGURAÇÃO (MASCARADA PARA SEGURANÇA/PORTFÓLIO)
# --------------------------------------------------------------------

# URL do Webhook do Power Automate (Anonimizada)
WORKFLOW_WEBHOOK_URL = "https://prod.powerautomate.com/workflows/SEU_WEBHOOK_AQUI"

# Configurações de SharePoint (Anonimizadas)
SHAREPOINT_SITE_URL = "https://empresa.sharepoint.com/sites/gestaoderede"
SHAREPOINT_TENANT_ROOT = "https://empresa.sharepoint.com"
SHAREPOINT_FILE_PATH = "/Informacoes Gerenciais/Controles Internos/DISTRIBUICAO/DISTRIBUICAO_OUVIDORIA.xlsx"
SHAREPOINT_FOLDER_PATH = "/Informacoes Gerenciais/Controles Internos/DISTRIBUICAO"

EXCEL_FILE_ABSOLUTE_URL = f"{SHAREPOINT_SITE_URL}{SHAREPOINT_FILE_PATH}"
EXCEL_DOWNLOAD_URL = (
    f"{SHAREPOINT_SITE_URL}/_layouts/15/download.aspx"
    f"?SourceUrl={quote(EXCEL_FILE_ABSOLUTE_URL, safe=':/')}"
)

# URL do Dashboard no Power BI (Anonimizada)
POWER_BI_URL = (
    "https://app.powerbi.com/reportEmbed?reportId=XXXXX-XXXX-XXXX&autoAuth=true&ctid=YYYY-YYYY-YYYY"
)

WORKFLOW_EXCEL_FILENAME = "DISTRIBUICAO_OUVIDORIA.xlsx"
EXCEL_SHEET_NAME = "NIP"
EXCEL_TABLE_NAME = "tb_NIP"

OK_STATUS_CODES = (200, 201, 202, 204)

# Tabela Delta alvo (Anonimizada para o padrão da Arquitetura Medallion)
TB_VW = "prd_gold.gestao_rede.tb_classificacao_beneficiario_norteamento_nip"

# Dicionário de E-mails (Dados sensíveis substituídos por valores genéricos)
ANALISTA_EMAIL_MAP = {
    "ANALISTA UM": "analista1@empresa.com.br",
    "ANALISTA DOIS": "analista2@empresa.com.br",
    "ANALISTA TRES": "analista3@empresa.com.br",
    "NOME_ANALISTA_FOCAL": "focal@empresa.com.br"
}

EXCEL_EXPORT_COLS = [
    "DT_INICIO_WORKFLOW", "DT_LIMITE_WORKFLOW", "HR_LIMITE_WORKFLOW",
    "SLA_WORKFLOW", "BACKLOG", "VENCEU_COM_REDE_NACIONAL",
    "DIAS_UTEIS_DECORRIDOS", "PERFIL_CRITICO_BENEFICIÁRIO", "FASE",
    "DISTRIBUICAO", "ANALISTA_SENDO_SUBSTITUIDO", "IDWORKFLOW",
    "PROCESSO", "COMPLEMENTO", "CODIDENTIFICACAO", "NOMEIDENTIFICACAO",
    "PLANO", "UF", "MUNICIPIO", "DT_INICIO_ATIVIDADE", "HR_INICIO_ATIVIDADE",
    "DT_LIMITE_ATIVIDADE", "HR_LIMITE_ATIVIDADE", "SLA_ATIVIDADE",
    "REVISAO_COMENTARIO_ROBO", "OBS",
]

# Nomes de processos sensíveis anonimizados
PROCESSO_PARA_GRUPO_CARD = {
    "AUTORIZAÇÃO ESPECIAL - GESTÃO REDE NACIONAL CLIENTES": "DEMAIS PROCESSOS",
    "AUTO DE INFRAÇÃO - ANS": "NIP",
    "ACOLHIMENTO COLABORADOR GRUPO CORPORATIVO": "DEMAIS PROCESSOS",
    "ACOLHIMENTO COLABORADOR GRUPO CONTROLADOR": "DEMAIS PROCESSOS",
    "ACOLHIMENTO DE CRÔNICOS": "DEMAIS PROCESSOS",
    "ACOLHIMENTO TEA": "DEMAIS PROCESSOS",
    "ATENDIMENTO INADEQUADO REDE CREDENCIADA": "DEMAIS PROCESSOS",
    "AUTORIZAÇÃO ESPECIAL CR URGÊNCIA - SADT INTERNADO": "DEMAIS PROCESSOS",
    "AUTORIZAÇÃO ESPECIAL NETWORK": "DEMAIS PROCESSOS",
    "AUTORIZAÇÃO ESPECIAL NIP/LIMINAR": "NIP",
    "AUTORIZAÇÃO ESPECIAL/EVENTUAL": "DEMAIS PROCESSOS",
    "AUTORIZAÇÃO ESPECIAL/REFERENCIADO": "DEMAIS PROCESSOS",
    "CICLO PRÉ-AUTO DE INFRAÇÃO ANS": "NIP",
    "COPARTICIPAÇÃO INDEVIDA": "DEMAIS PROCESSOS",
    "DESCREDENCIAMENTO": "DEMAIS PROCESSOS",
    "DOCUMENTO OUVIDORIA": "OUVIDORIA",
    "EXTRACONTRATUAL/LIBERALIDADE": "DEMAIS PROCESSOS",
    "GERENCIAR NIP ASSISTENCIAL (NOTIFICAÇÃO DE INVESTIGAÇÃO PRELIMINAR)": "NIP",
    "GERENCIAR NIP NÃO ASSISTENCIAL (NOTIFICAÇÃO DE INVESTIGAÇÃO PRELIMINAR)": "NIP",
    "IMPRENSA": "DEMAIS PROCESSOS",
    "INDICAÇÃO DE PROFISSIONAL PARA CREDENCIAMENTO": "DEMAIS PROCESSOS",
    "NEGOCIAÇÃO": "DEMAIS PROCESSOS",
    "NIP - OPERADORA PARCEIRA": "NIP",
    "NPS OPERADORA": "DEMAIS PROCESSOS",
    "ÓRGÃOS DE REPRESENTAÇÃO - 1 DIA": "OUVIDORIA",
    "ÓRGÃOS DE REPRESENTAÇÃO - 2 DIAS": "OUVIDORIA",
    "ÓRGÃOS DE REPRESENTAÇÃO - 3 DIAS": "OUVIDORIA",
    "ÓRGÃOS DE REPRESENTAÇÃO - 4 DIAS": "OUVIDORIA",
    "ÓRGÃOS DE REPRESENTAÇÃO - 6 DIAS": "OUVIDORIA",
    "OUVIDORIA - CLIENTE": "OUVIDORIA",
    "OUVIDORIA - CONSUMIDOR.GOV": "OUVIDORIA",
    "OUVIDORIA - OUTROS": "OUVIDORIA",
    "QUIMIOTERAPIA/RADIOTERAPIA": "DEMAIS PROCESSOS",
    "RECLAME AQUI - OPERADORA": "OUVIDORIA",
    "RECLAME AQUI - OPERADORA PARCEIRA": "OUVIDORIA",
    "REDES SOCIAIS": "DEMAIS PROCESSOS",
    "TEMPORÁRIOS": "DEMAIS PROCESSOS",
    "TEMPORÁRIOS - GESTÃO DE REDE NACIONAL": "DEMAIS PROCESSOS",
    "TEMPORÁRIOS - GESTÃO DE REDE REGIONAL": "DEMAIS PROCESSOS",
    "VENDA DE BENEFÍCIO PARA CONTRATOS PRÉ PAGAMENTO": "DEMAIS PROCESSOS",
    "VENDA DE BENEFÍCIO PARA PLANOS ADMINISTRADOS": "DEMAIS PROCESSOS",
}

# --------------------------------------------------------------------
# HELPERS GERAIS
# --------------------------------------------------------------------
def _payload_size_bytes(payload: dict) -> int:
    return len(json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))

def _body_preview(resp, max_chars: int = 1500) -> str:
    try:
        return (resp.text or "")[:max_chars]
    except Exception:
        return ""

def _response_has_delivery_error(resp) -> bool:
    body = (_body_preview(resp) or "").lower()
    suspicious_terms = [
        "webhook message delivery failed", "http error 400",
        "summary or text is required", "message size limit",
        "request entity too large", "payload too large",
        "bad payload", "invalid", "error",
    ]
    return any(term in body for term in suspicious_terms)

def _post_json(url: str, payload: dict, timeout: int = 300, retries: int = 3, backoff: float = 1.7):
    last_exc = None
    for attempt in range(1, retries + 1):
        try:
            resp = requests.post(
                url,
                headers={"Content-Type": "application/json; charset=utf-8"},
                json=payload,
                timeout=(8, timeout),
            )
            return resp
        except (requests.exceptions.ReadTimeout, requests.exceptions.ConnectionError) as e:
            last_exc = e
            sleep_s = backoff ** (attempt - 1)
            print(f"⚠️ POST falhou (tentativa {attempt}/{retries}) | erro={type(e).__name__}: {e} | aguardando {sleep_s:.1f}s")
            _time.sleep(sleep_s)
    raise last_exc

def _post_to_workflow(payload, timeout=300):
    payload_bytes = _payload_size_bytes(payload)
    print(f"📤 Enviando para Power Automate | payload_bytes={payload_bytes}")
    resp = _post_json(WORKFLOW_WEBHOOK_URL, payload, timeout=timeout, retries=3, backoff=1.7)
    print(f"📥 Power Automate status_code={resp.status_code} | body={_body_preview(resp)}")
    return resp

def _sleep_until_next_dispatch_slot(dt_obj, step_minutes=5):
    if (dt_obj.minute % step_minutes == 0 and dt_obj.second == 0 and dt_obj.microsecond == 0):
        return dt_obj
    next_minute = ((dt_obj.minute // step_minutes) + 1) * step_minutes
    if next_minute >= 60:
        target = (dt_obj.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1))
    else:
        target = dt_obj.replace(minute=next_minute, second=0, microsecond=0)
    wait_seconds = (target - dt_obj).total_seconds()
    if wait_seconds > 0:
        print(f"⏳ Aguardando até o próximo horário fechado: {target.strftime('%d/%m/%Y %H:%M:%S')} ({int(wait_seconds)}s)")
        _time.sleep(wait_seconds)
    return target

def _norm_name(s):
    return (s or "").strip().upper()

def _group_from_process(processo):
    return PROCESSO_PARA_GRUPO_CARD.get((processo or "").strip(), "SEM MAPEAMENTO")

def _build_mentions_emails_from_df(df_analistas, allowed_groups=None):
    rows = (
        df_analistas
        .select(
            F.col("DISTRIBUICAO").cast("string").alias("DISTRIBUICAO"),
            F.col("PROCESSO").cast("string").alias("PROCESSO"),
        )
        .where(F.col("DISTRIBUICAO").isNotNull())
        .where(F.trim(F.col("DISTRIBUICAO")) != "")
        .distinct()
        .collect()
    )
    emails = []
    missing = []
    for r in rows:
        grupo = _group_from_process(r["PROCESSO"])
        if allowed_groups and grupo not in allowed_groups:
            continue
        nome = _norm_name(r["DISTRIBUICAO"])
        email = ANALISTA_EMAIL_MAP.get(nome)
        if email:
            emails.append(email)
        else:
            missing.append(nome)
    return sorted(set(emails)), sorted(set(missing))

# --------------------------------------------------------------------
# HELPERS EXCEL
# --------------------------------------------------------------------
def _build_excel_bytes(sheet_name, cols, rows):
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment
    from openpyxl.utils import get_column_letter

    wb = Workbook()
    ws = wb.active
    ws.title = sheet_name
    ws.append(cols)
    for row in rows:
        ws.append(row)

    header_fill = PatternFill(fill_type="solid", fgColor="1F4E78")
    header_font = Font(color="FFFFFF", bold=True)
    for cell in ws[1]:
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = Alignment(horizontal="center", vertical="center")

    for col_idx, col_name in enumerate(cols, start=1):
        max_len = len(str(col_name))
        for row_idx in range(2, ws.max_row + 1):
            value = ws.cell(row=row_idx, column=col_idx).value
            max_len = max(max_len, len(str(value)) if value is not None else 0)
        ws.column_dimensions[get_column_letter(col_idx)].width = min(max(max_len + 2, 12), 40)

    bio = io.BytesIO()
    wb.save(bio)
    bio.seek(0)
    return bio.read()

def _encode_excel_to_base64(xlsx_bytes):
    return base64.b64encode(xlsx_bytes).decode("ascii")

# --------------------------------------------------------------------
# HELPERS ADAPTIVE CARD
# --------------------------------------------------------------------
def _num_item(label, value, color="default"):
    return {
        "type": "Container",
        "spacing": "Small",
        "items": [
            {"type": "TextBlock", "text": label, "wrap": True, "size": "Small", "isSubtle": True, "spacing": "None"},
            {"type": "TextBlock", "text": str(value), "wrap": True, "weight": "Bolder", "size": "Large", "color": color, "spacing": "None"},
        ],
    }

def _metric_columns(item):
    return {
        "type": "ColumnSet",
        "spacing": "Medium",
        "columns": [
            {"type": "Column", "width": "stretch", "items": [_num_item("Qtde", item["qtd"], "accent")]},
            {"type": "Column", "width": "stretch", "items": [_num_item("No Prazo", item["no_prazo"], "good")]},
            {"type": "Column", "width": "stretch", "items": [_num_item("Amanhã", item["vencendo_amanha"], "warning")]},
            {"type": "Column", "width": "stretch", "items": [_num_item("Hoje", item["vencendo_hoje"], "attention")]},
            {"type": "Column", "width": "stretch", "items": [_num_item("Vencido", item["vencido"], "attention")]},
        ],
    }

def _group_style(name):
    if name == "OUVIDORIA": return "good"
    if name == "NIP": return "attention"
    return "emphasis"

def _grupo_container(item):
    return {
        "type": "Container",
        "style": _group_style(item["grupo"]),
        "separator": True,
        "spacing": "Medium",
        "bleed": False,
        "items": [
            {"type": "TextBlock", "text": item["grupo"], "weight": "Bolder", "size": "Medium", "wrap": True},
            {"type": "TextBlock", "text": "Resumo consolidado do grupo", "wrap": True, "size": "Small", "isSubtle": True, "spacing": "None"},
            _metric_columns(item),
        ],
    }

def _build_teams_adaptive_card(saudacao, now_fmt, request_id, grupos_card, total_geral):
    body = [
        {
            "type": "Container",
            "style": "emphasis",
            "items": [
                {"type": "TextBlock", "text": saudacao, "wrap": True, "size": "Large", "weight": "Bolder"},
                {"type": "TextBlock", "text": "📌 Foto das demandas de NIP", "wrap": True, "weight": "Bolder", "spacing": "Small"},
                {"type": "TextBlock", "text": f"Atualizado em: {now_fmt} | Request ID: {request_id}", "wrap": True, "size": "Small", "isSubtle": True, "spacing": "None"},
            ],
        },
        {
            "type": "Container",
            "spacing": "Medium",
            "items": [
                {"type": "TextBlock", "text": "🤖 C.O.R.E - Consolidador Operacional de Registros e Estatísticas", "wrap": True, "weight": "Bolder", "spacing": "None"},
            ],
        },
    ]

    for item in grupos_card:
        body.append(_grupo_container(item))

    actions = []
    if EXCEL_DOWNLOAD_URL:
        actions.append({
            "type": "Action.OpenUrl",
            "title": "⬇️ Baixar Distribuição",
            "url": EXCEL_DOWNLOAD_URL,
        })
    if POWER_BI_URL:
        actions.append({
            "type": "Action.OpenUrl",
            "title": "📊 IR PARA BI - DISTRIBUIÇÃO",
            "url": POWER_BI_URL,
        })

    return {
        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        "type": "AdaptiveCard",
        "version": "1.5",
        "msteams": {"width": "full"},
        "body": body,
        "actions": actions,
    }

# --------------------------------------------------------------------
# 1) MONTA BASE DO EXCEL
# --------------------------------------------------------------------
tb_vw_df = spark.table(TB_VW).cache()

excel_export_df = (
    tb_vw_df
    .select(
        F.date_format(F.col("DT_INICIO_WORKFLOW"), "yyyy-MM-dd").alias("DT_INICIO_WORKFLOW"),
        F.date_format(F.col("DT_LIMITE_WORKFLOW"), "yyyy-MM-dd").alias("DT_LIMITE_WORKFLOW"),
        F.col("HR_LIMITE_WORKFLOW").cast("string").alias("HR_LIMITE_WORKFLOW"),
        F.col("SLA_WORKFLOW").cast("string").alias("SLA_WORKFLOW"),
        F.col("BACKLOG").cast("string").alias("BACKLOG"),
        F.col("VENCEU_COM_REDE_NACIONAL").cast("string").alias("VENCEU_COM_REDE_NACIONAL"),
        F.col("DIAS_UTEIS_DECORRIDOS").cast("int").alias("DIAS_UTEIS_DECORRIDOS"),
        F.col("PERFIL_CRITICO_BENEFICIÁRIO").cast("string").alias("PERFIL_CRITICO_BENEFICIÁRIO"),
        F.col("FASE").cast("string").alias("FASE"),
        F.col("DISTRIBUICAO").cast("string").alias("DISTRIBUICAO"),
        F.col("ANALISTA_SENDO_SUBSTITUIDO").cast("string").alias("ANALISTA_SENDO_SUBSTITUIDO"),
        F.col("IDWORKFLOW").cast("int").alias("IDWORKFLOW"),
        F.col("PROCESSO").cast("string").alias("PROCESSO"),
        F.col("COMPLEMENTO").cast("string").alias("COMPLEMENTO"),
        F.col("CODIDENTIFICACAO").cast("string").alias("CODIDENTIFICACAO"),
        F.col("NOMEIDENTIFICACAO").cast("string").alias("NOMEIDENTIFICACAO"),
        F.col("PLANO").cast("string").alias("PLANO"),
        F.col("UF").cast("string").alias("UF"),
        F.col("MUNICIPIO").cast("string").alias("MUNICIPIO"),
        F.date_format(F.col("DT_INICIO_ATIVIDADE"), "dd/MM/yyyy").alias("DT_INICIO_ATIVIDADE"),
        F.col("HR_INICIO_ATIVIDADE").cast("string").alias("HR_INICIO_ATIVIDADE"),
        F.date_format(F.col("DT_LIMITE_ATIVIDADE"), "dd/MM/yyyy").alias("DT_LIMITE_ATIVIDADE"),
        F.col("HR_LIMITE_ATIVIDADE").cast("string").alias("HR_LIMITE_ATIVIDADE"),
        F.col("SLA_ATIVIDADE").cast("string").alias("SLA_ATIVIDADE"),
        F.col("REVISAO_COMENTARIO_ROBO").cast("string").alias("REVISAO_COMENTARIO_ROBO"),
        F.col("OBS").cast("string").alias("OBS"),
    )
    .orderBy(F.col("DIAS_UTEIS_DECORRIDOS").desc())
)

excel_export_rows = [[row[c] for c in EXCEL_EXPORT_COLS] for row in excel_export_df.collect()]

mentions_emails_nip, mentions_missing_nip = _build_mentions_emails_from_df(
    excel_export_df, allowed_groups={"NIP"}
)
mentions_emails_ouvidoria_demais, mentions_missing_ouvidoria_demais = _build_mentions_emails_from_df(
    excel_export_df, allowed_groups={"OUVIDORIA", "DEMAIS PROCESSOS"}
)
mentions_emails_all = sorted(set(mentions_emails_nip + mentions_emails_ouvidoria_demais))
missing_all = sorted(set(mentions_missing_nip + mentions_missing_ouvidoria_demais))

if missing_all:
    print("⚠️ Analistas sem de-para de e-mail:", ", ".join(missing_all))
else:
    print("✅ Todos os analistas do Excel possuem de-para de e-mail.")

xlsx_bytes = _build_excel_bytes(EXCEL_SHEET_NAME, EXCEL_EXPORT_COLS, excel_export_rows)
excel_b64 = _encode_excel_to_base64(xlsx_bytes)

# --------------------------------------------------------------------
# 2) MONTA MÉTRICAS DO CARD
# --------------------------------------------------------------------
processo_map_expr = F.create_map(
    *[x for kv in PROCESSO_PARA_GRUPO_CARD.items() for x in (F.lit(kv[0]), F.lit(kv[1]))]
)

base = (
    tb_vw_df
    .select(
        F.col("IDWORKFLOW").cast("string").alias("IDWORKFLOW"),
        F.col("PROCESSO").cast("string").alias("PROCESSO"),
        F.col("SLA_WORKFLOW").cast("string").alias("SLA_WORKFLOW"),
    )
    .where(F.col("IDWORKFLOW").isNotNull())
    .withColumn(
        "GRUPO_CARD",
        F.when(F.col("PROCESSO").isNull() | (F.trim(F.col("PROCESSO")) == ""), F.lit("SEM PROCESSO"))
         .otherwise(F.coalesce(processo_map_expr[F.col("PROCESSO")], F.lit("SEM MAPEAMENTO")))
    )
)

SLA_VENCENDO_AMANHA = ["VENCENDO AMANHÃ", "VENCENDO AMANHA"]

_grupo_df = (
    base.groupBy("GRUPO_CARD")
    .agg(
        F.countDistinct("IDWORKFLOW").alias("QTD"),
        F.countDistinct(F.when(F.col("SLA_WORKFLOW") == F.lit("NO PRAZO"), F.col("IDWORKFLOW"))).alias("NO_PRAZO"),
        F.countDistinct(F.when(F.col("SLA_WORKFLOW").isin(SLA_VENCENDO_AMANHA), F.col("IDWORKFLOW"))).alias("VENCENDO_AMANHA"),
        F.countDistinct(F.when(F.col("SLA_WORKFLOW") == F.lit("VENCENDO HOJE"), F.col("IDWORKFLOW"))).alias("VENCENDO_HOJE"),
        F.countDistinct(F.when(F.col("SLA_WORKFLOW") == F.lit("VENCIDO"), F.col("IDWORKFLOW"))).alias("VENCIDO"),
    )
    .withColumn(
        "_ORDEM",
        F.when(F.col("GRUPO_CARD") == F.lit("OUVIDORIA"), F.lit(1))
         .when(F.col("GRUPO_CARD") == F.lit("NIP"), F.lit(2))
         .when(F.col("GRUPO_CARD") == F.lit("DEMAIS PROCESSOS"), F.lit(3))
         .when(F.col("GRUPO_CARD") == F.lit("SEM MAPEAMENTO"), F.lit(4))
         .otherwise(F.lit(5))
    )
    .orderBy(F.col("_ORDEM").asc(), F.col("QTD").desc(), F.col("GRUPO_CARD").asc())
)

GRUPOS_CARD = [
    {
        "grupo": r["GRUPO_CARD"] if r["GRUPO_CARD"] not in (None, "") else "SEM PROCESSO",
        "qtd": int(r["QTD"]),
        "no_prazo": int(r["NO_PRAZO"]),
        "vencendo_amanha": int(r["VENCENDO_AMANHA"]),
        "vencendo_hoje": int(r["VENCENDO_HOJE"]),
        "vencido": int(r["VENCIDO"]),
    }
    for r in _grupo_df.collect()
]

_total_geral_row = (
    base.agg(
        F.countDistinct("IDWORKFLOW").alias("QTD"),
        F.countDistinct(F.when(F.col("SLA_WORKFLOW") == F.lit("NO PRAZO"), F.col("IDWORKFLOW"))).alias("NO_PRAZO"),
        F.countDistinct(F.when(F.col("SLA_WORKFLOW").isin(SLA_VENCENDO_AMANHA), F.col("IDWORKFLOW"))).alias("VENCENDO_AMANHA"),
        F.countDistinct(F.when(F.col("SLA_WORKFLOW") == F.lit("VENCENDO HOJE"), F.col("IDWORKFLOW"))).alias("VENCENDO_HOJE"),
        F.countDistinct(F.when(F.col("SLA_WORKFLOW") == F.lit("VENCIDO"), F.col("IDWORKFLOW"))).alias("VENCIDO"),
    )
    .collect()[0]
)

TOTAL_GERAL = [
    int(_total_geral_row["QTD"]), int(_total_geral_row["NO_PRAZO"]),
    int(_total_geral_row["VENCENDO_AMANHA"]), int(_total_geral_row["VENCENDO_HOJE"]),
    int(_total_geral_row["VENCIDO"]),
]

# --------------------------------------------------------------------
# 3) AGUARDA SLOT, MONTA CARD E ENVIA TUDO AO POWER AUTOMATE
# --------------------------------------------------------------------
now = _sleep_until_next_dispatch_slot(datetime.now(TZ) if TZ else datetime.now(), step_minutes=5)
request_id = str(uuid.uuid4())
now_fmt = now.strftime("%d/%m/%Y %H:%M")
hhmm = now.time()

if time(5, 0) <= hhmm < time(11, 50):
    saudacao = "Bom dia!"
elif time(11, 50) <= hhmm < time(18, 0):
    saudacao = "Boa tarde!"
else:
    saudacao = "Boa noite!"

teams_card = _build_teams_adaptive_card(
    saudacao=saudacao, now_fmt=now_fmt, request_id=request_id,
    grupos_card=GRUPOS_CARD, total_geral=TOTAL_GERAL,
)

workflow_payload = {
    "target_sheet": "NIP",
    "table_name": "tb_NIP",
    "flow_mode": "excel_update_card",
    "request_id": request_id,
    "filename": WORKFLOW_EXCEL_FILENAME,
    "site_url": SHAREPOINT_SITE_URL,
    "folder_path": SHAREPOINT_FOLDER_PATH,
    "file_path": SHAREPOINT_FILE_PATH,
    "path": SHAREPOINT_FILE_PATH,
    "sheet_name": EXCEL_SHEET_NAME,
    "table_name": EXCEL_TABLE_NAME,
    "file_base64": excel_b64,
    "rows": excel_export_rows,
    "mentions_emails": mentions_emails_all,
    "mentions_emails_nip": mentions_emails_nip,
    "mentions_emails_ouvidoria_demais": mentions_emails_ouvidoria_demais,
    "generated_at": now.strftime("%Y-%m-%d %H:%M:%S"),
    "excel_download_url": EXCEL_DOWNLOAD_URL,
    "power_bi_url": POWER_BI_URL,
    "teams_card": teams_card,
    "summary": {
        "grupos_card": GRUPOS_CARD,
        "total_geral": TOTAL_GERAL,
        "analistas_sem_email": missing_all,
        "mentions_count": len(mentions_emails_all),
        "mentions_nip_count": len(mentions_emails_nip),
        "mentions_ouvidoria_demais_count": len(mentions_emails_ouvidoria_demais),
    },
}

resp = _post_to_workflow(workflow_payload, timeout=300)
workflow_ok = resp.status_code in OK_STATUS_CODES and not _response_has_delivery_error(resp)

if not workflow_ok:
    raise RuntimeError(
        "❌ Falha no Power Automate | "
        f"status={resp.status_code} | body={_body_preview(resp)} | request_id={request_id}"
    )

print(
    "✅ Mensageiro concluído via Power Automate | "
    f"status={resp.status_code} | request_id={request_id} | "
    f"linhas_excel={len(excel_export_rows)} | grupos_card={len(GRUPOS_CARD)}"
)