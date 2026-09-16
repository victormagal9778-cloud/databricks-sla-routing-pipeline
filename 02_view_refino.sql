%sql

CREATE OR REPLACE VIEW dbwsbx_bu_gestao_rede.workflow_gestao_de_rede_ouvidoria_nip AS
WITH
-- Somente 'Ativo' (usado para NOVO / RR quando NÃO existir ÂNCORA)
_cte_distribuicao_ativo AS (
  SELECT a.GRUPO, a.ANALISTA,
         ROW_NUMBER() OVER (PARTITION BY a.GRUPO ORDER BY a.ANALISTA) AS lin
  FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip a
  WHERE a.STATUS = 'Ativo'
    AND a.DtCarga = (SELECT MAX(DtCarga) FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip)
),
_cte_distribuicao_retorno AS (
  SELECT a.GRUPO, a.ANALISTA
  FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip a
  WHERE a.STATUS IN ('Ativo','Pausado')
    AND a.DtCarga = (SELECT MAX(DtCarga) FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip)
),
_cte_analista_qtd AS (
  SELECT GRUPO, COUNT(*) AS q_analistas
  FROM _cte_distribuicao_ativo
  GROUP BY GRUPO
),

-- [F3] ROUTE_GROUP: whitelist unificada ANCORA_1 + VIEW_3 (42 processos)
_cte_route_group_all_pre AS (
  SELECT
    WF.IDWORKFLOW,
    CASE
      WHEN C.DPROC_DS_PROCESSO IN (
        'OUVIDORIA - CLIENTE',
        'OUVIDORIA - CONSUMIDOR.GOV',
        'OUVIDORIA - OUTROS',
        'ÓRGÃOS DE REPRESENTAÇÃO - 1 DIA',
        'ÓRGÃOS DE REPRESENTAÇÃO - 2 DIAS',
        'ÓRGÃOS DE REPRESENTAÇÃO - 3 DIAS',
        'ÓRGÃOS DE REPRESENTAÇÃO - 4 DIAS',
        'ÓRGÃOS DE REPRESENTAÇÃO - 6 DIAS',
        'GERENCIAR NIP ASSISTENCIAL (NOTIFICAÇÃO DE INVESTIGAÇÃO PRELIMINAR)',
        'GERENCIAR NIP NÃO ASSISTENCIAL (NOTIFICAÇÃO DE INVESTIGAÇÃO PRELIMINAR)',
        'DOCUMENTO OUVIDORIA',
        'IMPRENSA',
        'RECLAME AQUI - OPERADORA',
        'RECLAME AQUI - POSTAL SAÚDE',
        'NIP - POSTAL SAÚDE',
        'ACOLHIMENTO COLABORADOR GRUPO OPERADORA',
        'ACOLHIMENTO COLABORADOR GRUPO OPERADORA',
        'ACOLHIMENTO DE CRÔNICOS',
        'ACOLHIMENTO TEA',
        'ATENDIMENTO INADEQUADO REDE CREDENCIADA',
        'AUTORIZAÇÃO ESPECIAL CR URGÊNCIA - SADT INTERNADO',
        'AUTORIZAÇÃO ESPECIAL NETWORK',
        'AUTORIZAÇÃO ESPECIAL NIP/LIMINAR',
        'AUTORIZAÇÃO ESPECIAL/EVENTUAL',
        'AUTORIZAÇÃO ESPECIAL/REFERENCIADO',
        'COPARTICIPAÇÃO INDEVIDA',
        'DESCREDENCIAMENTO',
        'EXTRACONTRATUAL/LIBERALIDADE',
        'INDICAÇÃO DE PROFISSIONAL PARA CREDENCIAMENTO',
        'NEGOCIAÇÃO',
        'NPS OPERADORA',
        'QUIMIOTERAPIA/RADIOTERAPIA',
        'TEMPORÁRIOS',
        'TEMPORÁRIOS - GESTÃO DE REDE NACIONAL',
        'TEMPORÁRIOS - GESTÃO DE REDE REGIONAL',
        'VENDA DE BENEFÍCIO PARA CONTRATOS PRÉ PAGAMENTO',
        'VENDA DE BENEFÍCIO PARA PLANOS ADMINISTRADOS',
        'REDES SOCIAIS',
        'DEMANDA CLIENTE (RCA)',
        'GESTÃO DE ACESSO REDE - EVENTUAL',
        'PRÉ-AUTO DE INFRAÇÃO ANS',
        'DNA ATENDE COLABORADOR'
      ) THEN C.DPROC_DS_PROCESSO
      ELSE G.DTPCI_DS_TIPO_COMPLEMENTO_ITEM
    END AS ROUTE_GROUP,
    ROW_NUMBER() OVER (PARTITION BY WF.IDWORKFLOW ORDER BY C.DPROC_DS_PROCESSO, WF.IDWORKFLOW) AS rn
  FROM dbwworkflow_cur_view.wfworkflowatividade A
  LEFT JOIN dbwworkflow_cur_view.wfprocessoatividade B ON A.IDATIVIDADE = B.IDATIVIDADE
  LEFT JOIN dbwOPERADORA_dw_view.dproc_processo C ON B.IDPROCESSO = C.DPROC_CD_PROCESSO
  LEFT JOIN dbwworkflow_cur_view.wfworkflow WF ON A.IDWORKFLOW = WF.IDWORKFLOW
  LEFT JOIN dbwworkflow_cur_view.wfgrupo F ON B.IDGRUPOREALIZADOR = F.IDGRUPO
  LEFT JOIN dbwOPERADORA_dw_view.dtpci_tipo_complemento_item G
         ON WF.IDTPCOMPLEMENTOITEM = G.DTPCI_CD_TIPO_COMPLEMENTO_ITEM
  WHERE F.DSCGRUPO = 'GESTÃO DE REDE NACIONAL'
),
_cte_route_group_all AS (
  SELECT IDWORKFLOW, ROUTE_GROUP
  FROM _cte_route_group_all_pre
  WHERE rn = 1
),

-- RR simples (fallback apenas quando NÃO existir ÂNCORA)
_rr_enum AS (
  SELECT rg.IDWORKFLOW, rg.ROUTE_GROUP,
         ROW_NUMBER() OVER (PARTITION BY rg.ROUTE_GROUP ORDER BY rg.IDWORKFLOW) AS rn
  FROM _cte_route_group_all rg
),
_rr_calc AS (
  SELECT e.*, aq.q_analistas,
         CASE WHEN aq.q_analistas = 0 THEN NULL ELSE ((e.rn - 1) % aq.q_analistas) + 1 END AS lin_destino
  FROM _rr_enum e
  LEFT JOIN _cte_analista_qtd aq ON aq.GRUPO = e.ROUTE_GROUP
),
_rr_result AS (
  SELECT c.IDWORKFLOW, c.ROUTE_GROUP, an.ANALISTA
  FROM _rr_calc c
  LEFT JOIN _cte_distribuicao_ativo an
         ON an.GRUPO = c.ROUTE_GROUP AND an.lin = c.lin_destino
),

-- RETORNO (fallback apenas quando NÃO existir ÂNCORA)
_ret_max AS (
  SELECT A.IDWORKFLOW, MAX(A.DTHRFIM) AS max_fim
  FROM dbwworkflow_cur_view.wfworkflowatividade A
  JOIN dbwworkflow_cur_view.wfprocessoatividade B ON A.IDATIVIDADE = B.IDATIVIDADE
  JOIN dbwworkflow_cur_view.wfgrupo F ON B.IDGRUPOREALIZADOR = F.IDGRUPO
  WHERE A.DESCRICAO <> 'ABERTURA'
    AND F.DSCGRUPO = 'GESTÃO DE REDE NACIONAL'
    AND A.IDWORKFLOW NOT IN (
      26530904, 26474288, 26336066, 26272688, 25339223
    )
  GROUP BY A.IDWORKFLOW
),
_retorno AS (
  SELECT
    A.IDWORKFLOW,
    E.DAGWO_NM_AGENTE,
    ROW_NUMBER() OVER (PARTITION BY A.IDWORKFLOW ORDER BY A.DTHRFIM DESC) AS rn
  FROM dbwworkflow_cur_view.wfworkflowatividade A
  JOIN dbwworkflow_cur_view.wfprocessoatividade B ON A.IDATIVIDADE = B.IDATIVIDADE
  JOIN dbwOPERADORA_dw_view.dagwo_agente_workflow E ON A.IDAGENTE = E.DAGWO_CD_AGENTE
  JOIN _ret_max M ON M.IDWORKFLOW = A.IDWORKFLOW AND M.max_fim = A.DTHRFIM
),
_retorno_ok AS (SELECT * FROM _retorno WHERE rn = 1),

-- =========================================================
-- REGRA FOCAL: direcionar/direcionamento -> KARINA (somente NIP)
-- [F2] _cte_karina_ativa_nip já filtra STATUS='Ativo':
--      focal inativa nunca dispara troca de analista
-- =========================================================
_cte_karina_ativa_nip AS (
  SELECT DISTINCT a.ANALISTA
  FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip a
  WHERE UPPER(TRIM(a.ANALISTA)) = 'KARINA AMANCIO RODRIGUES'
    AND a.STATUS = 'Ativo'
    AND UPPER(COALESCE(a.GRUPO, '')) LIKE '%NIP%'
    AND a.DtCarga = (SELECT MAX(DtCarga) FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip)
),
_cte_focal_direcionamento AS (
  SELECT DISTINCT
    WF.IDWORKFLOW,
    K.ANALISTA AS ANALISTA_FOCAL,
    'Coluna adaptada para analista focal de direcionamento.' AS REVISAO_FOCAL
  FROM dbwworkflow_cur_view.wfworkflow WF
  INNER JOIN _cte_karina_ativa_nip K ON 1 = 1
  LEFT JOIN dbwworkflow_cur_view.wfworkflowatividade A ON A.IDWORKFLOW = WF.IDWORKFLOW
  LEFT JOIN dbwworkflow_cur_view.wfprocessoatividade B ON A.IDATIVIDADE = B.IDATIVIDADE
  LEFT JOIN dbwOPERADORA_dw_view.dproc_processo C ON B.IDPROCESSO = C.DPROC_CD_PROCESSO
  WHERE (COALESCE(LOWER(WF.TEXTO), '') LIKE '%TRANS%'
      OR COALESCE(LOWER(WF.TEXTO), '') LIKE '%REDESIGNAÇÃO%')
    AND UPPER(COALESCE(C.DPROC_DS_PROCESSO, '')) LIKE '%NIP%'
),

-- =========================================================
-- HISTÓRICO DO MESMO ANALISTA ANCORADO (para revisar fase -> RETORNO)
-- =========================================================
_hist_analista_ancora AS (
  SELECT
    wa.idworkflow AS IDWORKFLOW,
    UPPER(TRIM(wa.analista)) AS ANALISTA_N,
    1 AS HAS_HIST
  FROM dbwsbx_bu_gestao_rede.workflow_atribuicao_ouvidoria_nip wa
  JOIN dbwworkflow_cur_view.wfworkflowatividade A
       ON A.IDWORKFLOW = wa.idworkflow
  JOIN dbwworkflow_cur_view.wfprocessoatividade B
       ON A.IDATIVIDADE = B.IDATIVIDADE
  JOIN dbwworkflow_cur_view.wfgrupo F
       ON B.IDGRUPOREALIZADOR = F.IDGRUPO
  JOIN dbwOPERADORA_dw_view.dagwo_agente_workflow E
       ON A.IDAGENTE = E.DAGWO_CD_AGENTE
  WHERE TO_DATE(A.DTHRFIM) <> DATE '1900-01-01'
    AND A.DESCRICAO <> 'ABERTURA'
    AND F.DSCGRUPO = 'GESTÃO DE REDE NACIONAL'
    AND A.IDWORKFLOW NOT IN (
      26530904, 26474288, 26336066, 26272688, 25339223
    )
    AND UPPER(TRIM(E.DAGWO_NM_AGENTE)) = UPPER(TRIM(wa.analista))
  GROUP BY wa.idworkflow, UPPER(TRIM(wa.analista))
),

-- =========================================================
-- STUBS para CTEs auxiliares não fornecidas (mantidas)
-- =========================================================
_cte_mo AS (
  SELECT CAST(NULL AS BIGINT) AS IDWORKFLOW, CAST(NULL AS STRING) AS MO WHERE 1=0
),
_cte_prestador AS (
  SELECT
    CAST(NULL AS STRING) AS DPRES_CD_PRESTADOR_SHOW,
    CAST(NULL AS STRING) AS GRUPO,
    CAST(NULL AS STRING) AS DPRES_SG_UF_PRESTADOR_PRINCIPAL,
    CAST(NULL AS STRING) AS DPRES_NM_SUB_TIPO_REDE,
    CAST(NULL AS DATE)   AS DT_EXCLUSAO
  WHERE 1=0
),
_cte_valores_reembolso_cobranca_indevida AS (
  SELECT CAST(NULL AS BIGINT) AS IDWORKFLOW, CAST(NULL AS STRING) AS VALOR WHERE 1=0
),
_cte_referencia_desconto AS (
  SELECT CAST(NULL AS BIGINT) AS IDWORKFLOW, CAST(NULL AS STRING) AS VALOR WHERE 1=0
),
_cte_nota AS (
  SELECT CAST(NULL AS BIGINT) AS IDWORKFLOW, CAST(NULL AS STRING) AS VALOR WHERE 1=0
),
_cte_desconto_aplicado AS (
  SELECT CAST(NULL AS BIGINT) AS IDWORKFLOW, CAST(NULL AS STRING) AS VALOR WHERE 1=0
),
_cte_desconto2 AS (
  SELECT CAST(NULL AS BIGINT) AS IDWORKFLOW, CAST(NULL AS STRING) AS VALOR WHERE 1=0
),
_cte_reversao AS (
  SELECT CAST(NULL AS BIGINT) AS IDWORKFLOW, CAST(NULL AS STRING) AS VALOR WHERE 1=0
),

-- =========================================================
-- BASE: define DISTRIBUICAO e FASE
-- [F1] INNER JOIN na âncora garante que somente workflows
--      já registrados aparecem na VIEW e na classificação
-- =========================================================
base AS (
  SELECT DISTINCT

    -- =====================
    -- DISTRIBUICAO (ANALISTA)
    -- [F1] Com INNER JOIN, WA.analista sempre NOT NULL.
    --      Focal (_cte_karina_ativa_nip) já filtra STATUS='Ativo'.
    -- =====================
    CASE
      WHEN FD.IDWORKFLOW IS NOT NULL THEN FD.ANALISTA_FOCAL
      ELSE WA.analista
    END AS DISTRIBUICAO,

    -- =====================
    -- FASE (revisão sobre o que está na âncora)
    -- =====================
    CASE
      WHEN FD.IDWORKFLOW IS NOT NULL THEN 'NOVO'
      WHEN COALESCE(WA.fase,'') = 'REDISTRIBUICAO' THEN 'REDISTRIBUICAO'
      WHEN COALESCE(HA.HAS_HIST, 0) = 1
        OR UPPER(TRIM(COALESCE(E.DAGWO_NM_AGENTE,''))) = UPPER(TRIM(COALESCE(WA.analista,'')))
        THEN 'RETORNO'
      ELSE COALESCE(WA.fase, 'NOVO')
    END AS FASE_DISTRIBUICAO,

    -- =====================
    -- DEMAIS CAMPOS (mantidos como no original)
    -- =====================
    B.IDPROCESSO,
    C.DPROC_DS_PROCESSO,
    G.DTPCI_DS_TIPO_COMPLEMENTO_ITEM AS COMPLEMENTO,
    E.DAGWO_NM_AGENTE,
    F.DSCGRUPO AS GRUPO_RESPONSAVEL,
    A.IDWORKFLOW,
    CAST(A.IDWORKFLOW AS STRING) AS IDWORKFLOWTEXTO,
    CASE
      WHEN O.GRUPO = '' THEN 'DEMAIS'
      WHEN O.GRUPO IS NULL THEN 'DEMAIS'
      ELSE O.GRUPO
    END AS GRUPO,
    O.DPRES_SG_UF_PRESTADOR_PRINCIPAL AS UF,
    O.DPRES_NM_SUB_TIPO_REDE AS TIPO_VINCULACAO,
    O.DT_EXCLUSAO,
    A.DESCRICAO,
    D.IDTPCOMPLEMENTOITEM AS ID_COMPLEMENTO,

    CASE
      WHEN B.IDPROCESSO <> '8201' THEN 0
      WHEN J.VALOR IS NULL THEN 0
      WHEN J.VALOR = '00,00' THEN 0
      WHEN J.VALOR IS NOT NULL THEN CAST(REPLACE(REPLACE(J.VALOR, '.', ''), ',', '.') AS DOUBLE)
    END AS VLR_REEMBOLSO,

    CASE
      WHEN B.IDPROCESSO = '6298' THEN 0
      WHEN B.IDPROCESSO = '8201' THEN 0
      WHEN N.VALOR = '' THEN 0
      WHEN N.VALOR = '00,00' THEN 0
      WHEN N.VALOR IS NOT NULL THEN CAST(REPLACE(REPLACE(N.VALOR, '.', ''), ',', '.') AS DOUBLE)
      WHEN N.VALOR IS NULL THEN 0
    END AS VALOR_DA_NOTA,

    CASE
      WHEN T.VALOR = '00,00' THEN 0
      WHEN T.VALOR = '' THEN 0
      WHEN T.VALOR IS NOT NULL THEN CAST(REPLACE(REPLACE(T.VALOR, '.', ''), ',', '.') AS DOUBLE)
      WHEN T.VALOR IS NULL THEN CAST(REPLACE(REPLACE(P.VALOR, '.', ''), ',', '.') AS DOUBLE)
      ELSE 0
    END AS DESCONTO2,

    CASE
      WHEN U.VALOR = '00,00' THEN 0
      WHEN U.VALOR = '' THEN 0
      WHEN U.VALOR IS NOT NULL THEN CAST(REPLACE(REPLACE(U.VALOR, '.', ''), ',', '.') AS DOUBLE)
      WHEN U.VALOR IS NULL THEN 0
    END AS REVERSAO,

    CASE
      WHEN B.IDPROCESSO <> '8201' THEN NULL
      WHEN M.VALOR IS NULL THEN NULL
      WHEN M.VALOR = 'NAO INFORMADO' THEN NULL
      WHEN M.VALOR IS NOT NULL THEN M.VALOR
    END AS REF_REEMBOLSO,

    K.MO,
    COALESCE(L.DBENE_NM_BENEFICIARIO, H.DBENE_NM_BENEFICIARIO) AS BENEFICIARIO,
    CASE WHEN H.DBENE_NM_GRAU_PARENTESCO = 'NAO INFORMADO' THEN '' ELSE H.DBENE_NM_GRAU_PARENTESCO END AS PARENTESCO,
    H.DTEMP_DT_INCLUSAO AS DT_INCLUSAO_BENEFICIARIO,
    CASE WHEN TO_DATE(H.DTEMP_DT_EXCLUSAO) = DATE '1900-01-01' THEN NULL ELSE TO_DATE(H.DTEMP_DT_EXCLUSAO) END AS DT_EXCLUSAO_BENEFICIARIO,
    H.DBENE_NM_TIPO_ASSOCIADO AS TIPO_ASSOCIADO,
    COALESCE(Q.DPLAN_NM_PRODUTO, S.DPLAN_NM_PRODUTO) AS PLANO,

    (K.MO || ' - ' || COALESCE(L.DBENE_NM_BENEFICIARIO, H.DBENE_NM_BENEFICIARIO)) AS MARCAOTICA_NOME,
    (D.CODIDENTIFICACAO || ' - ' || D.NOMEIDENTIFICACAO) AS COD_NOME,

    D.CODIDENTIFICACAO,
    D.NOMEIDENTIFICACAO,
    A.IDAGENTE,

    CASE WHEN TO_DATE(D.DTHRFIM) = DATE '1900-01-01' THEN 'ABERTO' ELSE 'FECHADO' END AS STATUS_PROCESSO,
    CASE WHEN TO_DATE(A.DTHRFIM) = DATE '1900-01-01' THEN 'ABERTO' ELSE 'FECHADO' END AS STATUS_ATIVIDADE,

    CASE
      WHEN A.OBSFECHAMENTO = 'NAO INFORMADO' THEN NULL
      ELSE REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
        A.OBSFECHAMENTO,'<P>',''),'<BR>',''),'</P>',' '),'<P>',' '),'&GT;',''),'&NBSP;',''),'</U>;',''),'</U>',''),'<U>',''),
        '>',''),'<B',''),'</B',''),'<!STARTFRAGMENT',''),'<!ENDFRAGMENT','')
    END AS OBSERVACAO_DEMANDA,

    TO_DATE(D.DTHRINICIO) AS DT_INICIO_WORKFLOW,
    DATE_FORMAT(D.DTHRINICIO,'MM-yyyy') AS MES_INICIO_WORKFLOW,
    TO_DATE(A.DTHRINICIO) AS DT_INICIO_ATIVIDADE,
    DATE_FORMAT(A.DTHRINICIO,'MM-yyyy') AS MES_INICIO_ATIVIDADE,
    DATE_FORMAT(A.DTHRINICIO,'HH:mm') AS HR_INICIO_ATIVIDADE,
    TO_DATE(A.DTHRFIMPREVISAO) AS DT_LIMITE_ATIVIDADE,
    DATE_FORMAT(A.DTHRFIMPREVISAO,'HH:mm') AS HR_LIMITE_ATIVIDADE,
    TO_DATE(D.DTLIMITE) AS DT_LIMITE_WORKFLOW,
    DATE_FORMAT(D.DTLIMITE,' HH:mm') AS HR_LIMITE_WORKFLOW,

    DATEDIFF(CURRENT_DATE(), TO_DATE(A.DTHRFIMPREVISAO)) AS QTDE_DIAS_VENCER_ATIVIDADE,

    CASE
      WHEN TO_DATE(A.DTHRFIM) = DATE '1900-01-01' THEN
        CASE
          WHEN CURRENT_DATE() > TO_DATE(A.DTHRFIMPREVISAO) THEN 'VENCIDO'
          WHEN CURRENT_DATE() = TO_DATE(A.DTHRFIMPREVISAO) THEN 'VENCENDO HOJE'
          WHEN DATE_ADD(CURRENT_DATE(), 1) = TO_DATE(A.DTHRFIMPREVISAO) THEN 'VENCENDO AMANHA'
          WHEN CURRENT_DATE() < TO_DATE(A.DTHRFIMPREVISAO) THEN 'NO PRAZO'
        END
      WHEN TO_DATE(A.DTHRFIM) > TO_DATE(A.DTHRFIMPREVISAO) THEN 'NO PRAZO'
      WHEN TO_DATE(A.DTHRFIM) = TO_DATE(A.DTHRFIMPREVISAO) THEN 'NO PRAZO'
      WHEN TO_DATE(A.DTHRFIM) < TO_DATE(A.DTHRFIMPREVISAO) THEN 'VENCIDO'
    END AS SLA_ATIVIDADE,

    CASE
      WHEN DATE_FORMAT(DATE_ADD(A.DTHRINICIO, 4), 'EEEE') = 'Saturday' THEN TO_DATE(DATE_ADD(A.DTHRINICIO, 5))
      WHEN DATE_FORMAT(DATE_ADD(A.DTHRINICIO, 4), 'EEEE') = 'Sunday' THEN TO_DATE(DATE_ADD(A.DTHRINICIO, 6))
      ELSE TO_DATE(DATE_ADD(A.DTHRINICIO, 4))
    END AS DT_LIMITE_CLIENTE_5DIASUTEIS,

    CASE WHEN TO_DATE(A.DTHRFIM) = DATE '1900-01-01' THEN NULL ELSE TO_DATE(A.DTHRFIM) END AS DT_ATIVIDADE_ENCERRADO,
    CASE WHEN TO_DATE(A.DTHRFIM) = DATE '1900-01-01' THEN NULL ELSE DATE_FORMAT(A.DTHRFIM,'HH:mm') END AS HR_ATIVIDADE_ENCERRADO,
    CASE WHEN TO_DATE(D.DTHRFIM) = DATE '1900-01-01' THEN NULL ELSE TO_DATE(D.DTHRFIM) END AS DT_PROCESSO_ENCERRADO,
    CASE WHEN TO_DATE(D.DTHRFIM) = DATE '1900-01-01' THEN NULL ELSE DATE_FORMAT(D.DTHRFIM,'HH:mm') END AS HR_PROCESSO_ENCERRADO,

    A.DtUltAtz,

    COALESCE(WA.motivo, NULL) AS MOTIVO_DISTRIBUICAO,

    -- Auxiliares
    RG.ROUTE_GROUP,
    WA.analista AS ANALISTA_WA,
    WA.fase     AS FASE_WA,
    COALESCE(HA.HAS_HIST, 0) AS HAS_HIST_WA,
    FD.REVISAO_FOCAL,

    CASE
      WHEN FD.IDWORKFLOW IS NOT NULL THEN FD.REVISAO_FOCAL
      WHEN WA.analista IS NOT NULL AND COALESCE(WA.fase,'NOVO') <>
        (CASE
           WHEN COALESCE(WA.fase,'') = 'REDISTRIBUICAO' THEN 'REDISTRIBUICAO'
           WHEN COALESCE(HA.HAS_HIST, 0) = 1
             OR UPPER(TRIM(COALESCE(E.DAGWO_NM_AGENTE,''))) = UPPER(TRIM(COALESCE(WA.analista,'')))
             THEN 'RETORNO'
           ELSE COALESCE(WA.fase, 'NOVO')
         END)
        THEN CONCAT('FASE_REVISADA: ', COALESCE(WA.fase,'NOVO'), ' -> ',
                    (CASE
                       WHEN COALESCE(WA.fase,'') = 'REDISTRIBUICAO' THEN 'REDISTRIBUICAO'
                       WHEN COALESCE(HA.HAS_HIST, 0) = 1
                         OR UPPER(TRIM(COALESCE(E.DAGWO_NM_AGENTE,''))) = UPPER(TRIM(COALESCE(WA.analista,'')))
                         THEN 'RETORNO'
                       ELSE COALESCE(WA.fase, 'NOVO')
                     END))
      ELSE NULL
    END AS REVISAO,

    ROW_NUMBER() OVER (PARTITION BY A.IDWORKFLOW ORDER BY C.DPROC_DS_PROCESSO, A.IDWORKFLOW) AS rn_final

  FROM dbwworkflow_cur_view.wfworkflowatividade A
  LEFT JOIN dbwworkflow_cur_view.wfprocessoatividade B ON A.IDATIVIDADE = B.IDATIVIDADE
  LEFT JOIN dbwOPERADORA_dw_view.dproc_processo C ON B.IDPROCESSO = C.DPROC_CD_PROCESSO
  LEFT JOIN dbwworkflow_cur_view.wfworkflow D ON A.IDWORKFLOW = D.IDWORKFLOW
  LEFT JOIN dbwOPERADORA_dw_view.dagwo_agente_workflow E ON A.IDAGENTE = E.DAGWO_CD_AGENTE
  LEFT JOIN dbwworkflow_cur_view.wfgrupo F ON B.IDGRUPOREALIZADOR = F.IDGRUPO
  LEFT JOIN dbwOPERADORA_dw_view.dtpci_tipo_complemento_item G
         ON D.IDTPCOMPLEMENTOITEM = G.DTPCI_CD_TIPO_COMPLEMENTO_ITEM

  LEFT JOIN _cte_route_group_all RG ON RG.IDWORKFLOW = A.IDWORKFLOW
  LEFT JOIN _rr_result WR          ON WR.IDWORKFLOW = A.IDWORKFLOW

  -- [F1] INNER JOIN: somente workflows registrados na âncora aparecem
  INNER JOIN dbwsbx_bu_gestao_rede.workflow_atribuicao_ouvidoria_nip WA
          ON WA.idworkflow = A.IDWORKFLOW

  LEFT JOIN _retorno_ok RO ON RO.IDWORKFLOW = A.IDWORKFLOW

  LEFT JOIN _hist_analista_ancora HA
         ON HA.IDWORKFLOW = A.IDWORKFLOW
        AND HA.ANALISTA_N = UPPER(TRIM(COALESCE(WA.analista,'')))

  LEFT JOIN _cte_focal_direcionamento FD ON FD.IDWORKFLOW = A.IDWORKFLOW

  LEFT JOIN _cte_mo K ON A.IDWORKFLOW = K.IDWORKFLOW
  LEFT JOIN dbwOPERADORA_dw_view.dbene_beneficiario L ON D.CODIDENTIFICACAO = L.DBENE_NR_MARCA_OTICA
  LEFT JOIN dbwOPERADORA_dw_view.dbene_beneficiario H ON K.MO = H.DBENE_NR_MARCA_OTICA
  LEFT JOIN dbwOPERADORA_dw_view.dplan_plano S ON H.DBENE_CD_PLANO = S.DPLAN_CD_PLANO
  LEFT JOIN dbwOPERADORA_dw_view.dplan_plano Q ON L.DBENE_CD_PLANO = Q.DPLAN_CD_PLANO

  LEFT JOIN _cte_valores_reembolso_cobranca_indevida J ON A.IDWORKFLOW = J.IDWORKFLOW
  LEFT JOIN _cte_referencia_desconto M                 ON A.IDWORKFLOW = M.IDWORKFLOW
  LEFT JOIN _cte_nota N                                ON A.IDWORKFLOW = N.IDWORKFLOW
  LEFT JOIN _cte_desconto_aplicado P                   ON A.IDWORKFLOW = P.IDWORKFLOW
  LEFT JOIN _cte_desconto2 T                           ON A.IDWORKFLOW = T.IDWORKFLOW
  LEFT JOIN _cte_prestador O                           ON O.DPRES_CD_PRESTADOR_SHOW = D.CODIDENTIFICACAO
  LEFT JOIN _cte_reversao U                            ON A.IDWORKFLOW = U.IDWORKFLOW

  WHERE
    TO_DATE(D.DTHRFIM) = DATE '1900-01-01'
    AND TO_DATE(D.DTHRCANCELAMENTO) = DATE '1900-01-01'
    AND B.IDPROCESSO IN (
      '8259','8260','208','1596','1597','2757','2758','2759','3586','6116','6117','6118','6298','6299','6300','6478',
      '6627','6628','6680','6681','6843','7292','7293','7294','7295','7296','7297','7298','7299','7300','7301',
      '7362','7363','7364','7501','7579','7580','7717','7718','8003','8004','8437','8439','8439','8450','8452',
      '6770','6788','6933','6953','6954','7056','7073','7082','7093','7099','7137','7163','7179','7249','7308',
      '7372','7373','7522','7534','7777','7824','7848','7999','8153','8191','8192','8193','8226','8235','8423',
      '8415','5095','5876','8330','5418'
    )
    AND TO_DATE(A.DTHRFIM) = DATE '1900-01-01'
    AND F.DSCGRUPO = 'GESTÃO DE REDE NACIONAL'
    AND A.IDWORKFLOW NOT IN (
      26530904, 26474288, 26336066, 26272688, 25339223
    )
)

SELECT
  DISTRIBUICAO,
  FASE_DISTRIBUICAO,
  IDPROCESSO,
  DPROC_DS_PROCESSO,
  COMPLEMENTO,
  DAGWO_NM_AGENTE,
  GRUPO_RESPONSAVEL,
  IDWORKFLOW,
  IDWORKFLOWTEXTO,
  GRUPO,
  UF,
  TIPO_VINCULACAO,
  DT_EXCLUSAO,
  DESCRICAO,
  ID_COMPLEMENTO,
  VLR_REEMBOLSO,
  VALOR_DA_NOTA,
  DESCONTO2,
  REVERSAO,
  REF_REEMBOLSO,
  MO,
  BENEFICIARIO,
  PARENTESCO,
  DT_INCLUSAO_BENEFICIARIO,
  DT_EXCLUSAO_BENEFICIARIO,
  TIPO_ASSOCIADO,
  PLANO,
  MARCAOTICA_NOME,
  COD_NOME,
  CODIDENTIFICACAO,
  NOMEIDENTIFICACAO,
  IDAGENTE,
  STATUS_PROCESSO,
  STATUS_ATIVIDADE,
  OBSERVACAO_DEMANDA,
  DT_INICIO_WORKFLOW,
  MES_INICIO_WORKFLOW,
  DT_INICIO_ATIVIDADE,
  MES_INICIO_ATIVIDADE,
  HR_INICIO_ATIVIDADE,
  DT_LIMITE_ATIVIDADE,
  HR_LIMITE_ATIVIDADE,
  DT_LIMITE_WORKFLOW,
  HR_LIMITE_WORKFLOW,
  QTDE_DIAS_VENCER_ATIVIDADE,
  SLA_ATIVIDADE,
  DT_LIMITE_CLIENTE_5DIASUTEIS,
  DT_ATIVIDADE_ENCERRADO,
  HR_ATIVIDADE_ENCERRADO,
  DT_PROCESSO_ENCERRADO,
  HR_PROCESSO_ENCERRADO,
  DtUltAtz,
  MOTIVO_DISTRIBUICAO,
  REVISAO
FROM base
WHERE rn_final = 1
  AND DT_PROCESSO_ENCERRADO IS NULL;

-- =============================================================
-- ETL de apoio: atualiza FASE e dt_ult_atz na âncora
-- [F2] Analista só muda se:
--      1) Focal ATIVA (STATUS='Ativo' na DNA) — origem FOCAL_DIRECIONAMENTO
--      2) Analista atual com STATUS='Redistribuir' na DNA
--      Ativo e Pausado: intocáveis
-- =============================================================

MERGE INTO dbwsbx_bu_gestao_rede.workflow_atribuicao_ouvidoria_nip AS T
USING (
  SELECT
    IDWORKFLOW,
    DISTRIBUICAO,
    FASE_DISTRIBUICAO,
    CASE WHEN REVISAO = 'Coluna adaptada para analista focal de direcionamento.' THEN 1 ELSE 0 END AS APLICA_FOCAL,
    REVISAO
  FROM dbwsbx_bu_gestao_rede.workflow_gestao_de_rede_ouvidoria_nip
) AS S
ON T.IDWORKFLOW = S.IDWORKFLOW
WHEN MATCHED THEN
  UPDATE SET
    T.fase       = S.FASE_DISTRIBUICAO,
    T.dt_ult_atz = CURRENT_TIMESTAMP(),

    -- [F2] Prioridade de troca de analista:
    --   1) Focal ativa → troca
    --   2) Redistribuir → troca
    --   3) Ativo / Pausado / Focal inativa → intocável
    T.analista = CASE
      WHEN S.APLICA_FOCAL = 1
        AND EXISTS (
          SELECT 1
          FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip dna
          WHERE UPPER(TRIM(dna.ANALISTA)) = UPPER(TRIM(S.DISTRIBUICAO))
            AND dna.STATUS = 'Ativo'
            AND dna.DtCarga = (SELECT MAX(DtCarga) FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip)
        )
        THEN S.DISTRIBUICAO
      WHEN EXISTS (
        SELECT 1
        FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip dna
        WHERE UPPER(TRIM(dna.ANALISTA)) = UPPER(TRIM(T.analista))
          AND dna.STATUS = 'Redistribuir'
          AND dna.DtCarga = (SELECT MAX(DtCarga) FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip)
      )
        THEN S.DISTRIBUICAO
      ELSE T.analista
    END,

    T.origem = CASE
      WHEN S.APLICA_FOCAL = 1
        AND EXISTS (
          SELECT 1
          FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip dna
          WHERE UPPER(TRIM(dna.ANALISTA)) = UPPER(TRIM(S.DISTRIBUICAO))
            AND dna.STATUS = 'Ativo'
            AND dna.DtCarga = (SELECT MAX(DtCarga) FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip)
        )
        THEN 'FOCAL_DIRECIONAMENTO'
      ELSE T.origem
    END,

    T.motivo = CASE
      WHEN S.APLICA_FOCAL = 1
        AND EXISTS (
          SELECT 1
          FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip dna
          WHERE UPPER(TRIM(dna.ANALISTA)) = UPPER(TRIM(S.DISTRIBUICAO))
            AND dna.STATUS = 'Ativo'
            AND dna.DtCarga = (SELECT MAX(DtCarga) FROM dbwsbx_bu_gestao_rede.dna_ouvidoria_nip)
        )
        THEN S.REVISAO
      ELSE T.motivo
    END
;
