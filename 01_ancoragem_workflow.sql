%sql 
 
CREATE OR REPLACE TEMP VIEW _atividade_aberta_corrente_CI AS 
WITH base AS ( 
 SELECT 
 A.IDWORKFLOW, 

P
 A.IDATIVIDADE, 
 A.DTHRINICIO, 
 A.DTHRFIM, 
 F.DSCGRUPO AS grupo_atual, 
 E.DAGWO_NM_AGENTE AS agente_atual, 
 ROW_NUMBER() OVER ( 
 PARTITION BY A.IDWORKFLOW 
 ORDER BY A.DTHRINICIO DESC, A.IDATIVIDADE DESC, A.IDAGENTE DESC 
 ) AS rn 
 FROM dbw.tabela.wfworkflowatividade A 
 JOIN dbw.tabela.wfprocessoatividade B ON A.IDATIVIDADE = B.IDATIVIDADE 
 JOIN dbw.tabela.wfgrupo F ON B.IDGRUPOREALIZADOR = F.IDGRUPO 
 LEFT JOIN dbw.OPERADORA_dw_view.dagwo_agente_workflow E ON A.IDAGENTE = E.DAGWO_CD_AGENTE 
 WHERE TO_DATE(A.DTHRFIM) = DATE '1900-01-01' 
) 
SELECT * 
FROM base 
WHERE rn = 1; 

-- [F3] _rg_all: whitelist unificada ANCORA_1 + VIEW_3 (42 processos)
CREATE OR REPLACE TEMP VIEW _rg_all AS 
WITH _rg_all_pre AS ( 
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
 ROW_NUMBER() OVER ( 
 PARTITION BY WF.IDWORKFLOW 
 ORDER BY C.DPROC_DS_PROCESSO, WF.IDWORKFLOW 
 ) AS rn 
 FROM dbw.tabela.wfworkflowatividade A 
 LEFT JOIN dbw.tabela.wfprocessoatividade B ON A.IDATIVIDADE = B.IDATIVIDADE 
 LEFT JOIN dbw.OPERADORA_dw_view.dproc_processo C ON B.IDPROCESSO = C.DPROC_CD_PROCESSO 
 LEFT JOIN dbw.tabela.wfworkflow WF ON A.IDWORKFLOW = WF.IDWORKFLOW 
 LEFT JOIN dbw.tabela.wfgrupo F ON B.IDGRUPOREALIZADOR = F.IDGRUPO 
 LEFT JOIN dbw.OPERADORA_dw_view.dtpci_tipo_complemento_item G ON WF.IDTPCOMPLEMENTOITEM = G.DTPCI_CD_TIPO_COMPLEMENTO_ITEM 
 WHERE F.DSCGRUPO = 'GESTÃO DE REDE NACIONAL' 
) 
SELECT IDWORKFLOW, ROUTE_GROUP 
FROM _rg_all_pre 
WHERE rn = 1; 

-- ============================================================= 
-- 1) RETORNO — AJUSTADO (SOMENTE COM HISTÓRICO FINALIZADO) 
-- ============================================================= 
CREATE OR REPLACE TEMP VIEW vw_atribuicao_retorno AS 
WITH 
_wf_aberto AS ( 
 SELECT D.IDWORKFLOW 
 FROM dbw.tabela.wfworkflow D 
 WHERE TO_DATE(D.DTHRFIM) = DATE '1900-01-01' 
 AND TO_DATE(D.DTHRCANCELAMENTO) = DATE '1900-01-01' 
), 
_ret_max AS ( 
 SELECT A.IDWORKFLOW, MAX(A.DTHRFIM) AS max_fim 
 FROM dbw.tabela.wfworkflowatividade A 
 JOIN dbw.tabela.wfprocessoatividade B ON A.IDATIVIDADE = B.IDATIVIDADE 
 JOIN dbw.tabela.wfgrupo F ON B.IDGRUPOREALIZADOR = F.IDGRUPO 
 WHERE  TO_DATE(A.DTHRFIM) <> DATE '1900-01-01'
  AND A.DESCRICAO <> 'ABERTURA' 
 AND F.DSCGRUPO = 'GESTÃO DE REDE NACIONAL' 
 GROUP BY A.IDWORKFLOW 
), 
_retorno_ok AS ( 
 SELECT IDWORKFLOW, AGENTE_RETORNO 
 FROM ( 
   SELECT 
   A.IDWORKFLOW, 
   E.DAGWO_NM_AGENTE AS AGENTE_RETORNO, 
   ROW_NUMBER() OVER (PARTITION BY A.IDWORKFLOW ORDER BY A.DTHRFIM DESC, A.IDATIVIDADE DESC, A.IDAGENTE DESC) AS rn 
   FROM dbw.tabela.wfworkflowatividade A 
   JOIN dbw.tabela.wfprocessoatividade B ON A.IDATIVIDADE = B.IDATIVIDADE 
   JOIN dbw.OPERADORA_dw_view.dagwo_agente_workflow E ON A.IDAGENTE = E.DAGWO_CD_AGENTE 
   JOIN _ret_max M ON M.IDWORKFLOW = A.IDWORKFLOW AND M.max_fim = A.DTHRFIM 
 ) x 
 WHERE rn = 1 
), 
_dna_retorno AS ( 
 SELECT a.GRUPO, a.ANALISTA 
 FROM dbw.sbx_bu_gestao_rede.dna_ouvidoria_nip a 
 WHERE a.STATUS IN ('Ativo','Pausado') 
 AND a.DtCarga = ( 
 SELECT MAX(DtCarga) 
 FROM dbw.sbx_bu_gestao_rede.dna_ouvidoria_nip 
 ) 
) 
SELECT 
v.IDWORKFLOW, 
rg.ROUTE_GROUP AS route_group, 
ro.AGENTE_RETORNO AS analista, 
'RETORNO' AS fase, 
'RETORNO_DIRECT' AS origem, 
current_timestamp() AS dt_atribuicao, 
current_timestamp() AS dt_ult_atz, 
NULL AS motivo 
FROM _atividade_aberta_corrente_CI v 
JOIN _rg_all rg ON rg.IDWORKFLOW = v.IDWORKFLOW 
JOIN _retorno_ok ro ON ro.IDWORKFLOW = v.IDWORKFLOW 
JOIN _dna_retorno dn ON dn.GRUPO = rg.ROUTE_GROUP AND dn.ANALISTA = ro.AGENTE_RETORNO 
LEFT JOIN dbw.sbx_bu_gestao_rede.workflow_atribuicao_ouvidoria_nip wa ON wa.idworkflow = v.IDWORKFLOW 
WHERE v.grupo_atual = 'GESTÃO DE REDE NACIONAL' 
AND wa.idworkflow IS NULL 
AND EXISTS (SELECT 1 FROM _wf_aberto x WHERE x.IDWORKFLOW = v.IDWORKFLOW) 
QUALIFY ROW_NUMBER() OVER (PARTITION BY v.IDWORKFLOW ORDER BY v.IDWORKFLOW) = 1; 

MERGE INTO dbw.sbx_bu_gestao_rede.workflow_atribuicao_ouvidoria_nip AS T 
USING vw_atribuicao_retorno AS S 
ON T.idworkflow = S.idworkflow 
WHEN NOT MATCHED THEN INSERT ( 
 idworkflow, analista, route_group, fase, origem, dt_atribuicao, dt_ult_atz, motivo 
) VALUES ( 
 S.idworkflow, S.analista, S.route_group, S.fase, S.origem, S.dt_atribuicao, S.dt_ult_atz, S.motivo 
); 

-- ============================================================= 
-- 2) AGENTE ATUAL 
-- ============================================================= 
CREATE OR REPLACE TEMP VIEW vw_atribuicao_agente_atual AS 
WITH 
_wf_aberto AS ( 
 SELECT D.IDWORKFLOW 
 FROM dbw.tabela.wfworkflow D 
 WHERE TO_DATE(D.DTHRFIM) = DATE '1900-01-01' 
 AND TO_DATE(D.DTHRCANCELAMENTO) = DATE '1900-01-01' 
) ,
_dna_posse AS (
 SELECT a.GRUPO, a.ANALISTA
 FROM dbw.sbx_bu_gestao_rede.dna_ouvidoria_nip a
 WHERE a.STATUS IN ('Ativo','Pausado')
   AND a.DtCarga = (SELECT MAX(DtCarga) FROM dbw.sbx_bu_gestao_rede.dna_ouvidoria_nip)
)
SELECT 
 cur.IDWORKFLOW, 
 rg.ROUTE_GROUP AS route_group, 
 cur.agente_atual AS analista, 
 'RETORNO' AS fase, 
 'AGENTE_ATUAL_FLOW' AS origem, 
 current_timestamp() AS dt_atribuicao, 
 current_timestamp() AS dt_ult_atz, 
 CONCAT('Ancoragem do agente atual aberto no workflow: [', COALESCE(cur.agente_atual, 'NULL'), ']') AS motivo 
FROM _atividade_aberta_corrente_CI cur 
JOIN _wf_aberto wf 
 ON wf.IDWORKFLOW = cur.IDWORKFLOW 
JOIN _rg_all rg 
 ON rg.IDWORKFLOW = cur.IDWORKFLOW 
JOIN _dna_posse dn
  ON dn.GRUPO = rg.ROUTE_GROUP
 AND UPPER(TRIM(dn.ANALISTA)) = UPPER(TRIM(cur.agente_atual))
LEFT JOIN dbw.sbx_bu_gestao_rede.workflow_atribuicao_ouvidoria_nip wa 
 ON wa.idworkflow = cur.IDWORKFLOW 
WHERE cur.grupo_atual = 'GESTÃO DE REDE NACIONAL' 
AND COALESCE(UPPER(TRIM(cur.agente_atual)), 'NAO INFORMADO') <> 'NAO INFORMADO' 
AND wa.idworkflow IS NULL 
AND NOT EXISTS ( 
 SELECT 1 
 FROM vw_atribuicao_retorno r 
 WHERE r.IDWORKFLOW = cur.IDWORKFLOW 
) 
QUALIFY ROW_NUMBER() OVER (PARTITION BY cur.IDWORKFLOW ORDER BY cur.IDWORKFLOW) = 1; 

MERGE INTO dbw.sbx_bu_gestao_rede.workflow_atribuicao_ouvidoria_nip AS T 
USING vw_atribuicao_agente_atual AS S 
ON T.idworkflow = S.idworkflow 
WHEN NOT MATCHED THEN INSERT ( 
 idworkflow, analista, route_group, fase, origem, dt_atribuicao, dt_ult_atz, motivo 
) VALUES ( 
 S.idworkflow, S.analista, S.route_group, S.fase, S.origem, S.dt_atribuicao, S.dt_ult_atz, S.motivo 
); 

-- ============================================================= 
-- 3) NOVO 
-- ============================================================= 
CREATE OR REPLACE TEMP VIEW vw_atribuicao_novo AS 
WITH 
_wf_aberto AS ( 
 SELECT D.IDWORKFLOW 
 FROM dbw.tabela.wfworkflow D 
 WHERE TO_DATE(D.DTHRFIM) = DATE '1900-01-01' 
 AND TO_DATE(D.DTHRCANCELAMENTO) = DATE '1900-01-01' 
), 
_ativos AS ( 
 SELECT DISTINCT 
 a.GRUPO AS GRUPO_RAW, 
 a.ANALISTA AS ANALISTA_RAW, 
 TRANSLATE( 
 UPPER(TRIM(a.GRUPO)), 
 'ÁÀÃÂÉÈÊÍÌÎÓÒÕÔÚÙÛÇ', 
 'AAAAEEEIIIOOOOUUUC' 
 ) AS GRUPO_N, 
 UPPER(TRIM(a.ANALISTA)) AS ANALISTA_N 
 FROM dbw.sbx_bu_gestao_rede.dna_ouvidoria_nip a 
 WHERE a.STATUS = 'Ativo' 
 AND a.DtCarga = ( 
 SELECT MAX(DtCarga) 
 FROM dbw.sbx_bu_gestao_rede.dna_ouvidoria_nip 
 ) 
), 
_carga AS ( 
 SELECT 
 TRANSLATE( 
 UPPER(TRIM(wa.route_group)), 
 'ÁÀÃÂÉÈÊÍÌÎÓÒÕÔÚÙÛÇ', 
 'AAAAEEEIIIOOOOUUUC' 
 ) AS GRUPO_N, 
 UPPER(TRIM(wa.analista)) AS ANALISTA_N, 
 COUNT(*) AS carga 
 FROM dbw.sbx_bu_gestao_rede.workflow_atribuicao_ouvidoria_nip wa 
 INNER JOIN _wf_aberto w ON w.IDWORKFLOW = wa.idworkflow 
 GROUP BY 
 TRANSLATE( 
 UPPER(TRIM(wa.route_group)), 
 'ÁÀÃÂÉÈÊÍÌÎÓÒÕÔÚÙÛÇ', 
 'AAAAEEEIIIOOOOUUUC' 
 ), 
 UPPER(TRIM(wa.analista)) 
), 
_ativos_carga AS ( 
 SELECT 
 a.GRUPO_RAW, 
 a.ANALISTA_RAW, 
 a.GRUPO_N, 
 a.ANALISTA_N, 
 COALESCE(c.carga, 0) AS carga 
 FROM _ativos a 
 LEFT JOIN _carga c 
 ON c.GRUPO_N = a.GRUPO_N 
 AND c.ANALISTA_N = a.ANALISTA_N 
), 
_stats AS ( 
 SELECT GRUPO_N, AVG(carga) AS media 
 FROM _ativos_carga 
 GROUP BY GRUPO_N 
), 
_novos_candidatos AS ( 
 SELECT 
 cur.IDWORKFLOW, 
 RG.ROUTE_GROUP AS ROUTE_GROUP_RAW, 
 TRANSLATE( 
 UPPER(TRIM(RG.ROUTE_GROUP)), 
 'ÁÀÃÂÉÈÊÍÌÎÓÒÕÔÚÙÛÇ', 
 'AAAAEEEIIIOOOOUUUC' 
 ) AS ROUTE_GROUP_N, 
 ROW_NUMBER() OVER ( 
 PARTITION BY TRANSLATE( 
 UPPER(TRIM(RG.ROUTE_GROUP)), 
 'ÁÀÃÂÉÈÊÍÌÎÓÒÕÔÚÙÛÇ', 
 'AAAAEEEIIIOOOOUUUC' 
 ) 
 ORDER BY cur.IDWORKFLOW 
 ) AS rn 
 FROM _atividade_aberta_corrente_CI cur 
 JOIN _wf_aberto wf ON wf.IDWORKFLOW = cur.IDWORKFLOW 
 LEFT JOIN _rg_all RG ON RG.IDWORKFLOW = cur.IDWORKFLOW 
 LEFT JOIN dbw.sbx_bu_gestao_rede.workflow_atribuicao_ouvidoria_nip WA ON WA.idworkflow = cur.IDWORKFLOW 
 WHERE cur.grupo_atual = 'GESTÃO DE REDE NACIONAL' 
 AND WA.idworkflow IS NULL 
 AND RG.ROUTE_GROUP IS NOT NULL 
 QUALIFY ROW_NUMBER() OVER (PARTITION BY cur.IDWORKFLOW ORDER BY cur.IDWORKFLOW) = 1 
), 
_ativos_rank AS ( 
 SELECT 
 ac.GRUPO_RAW, 
 ac.ANALISTA_RAW, 
 ac.GRUPO_N, 
 ac.ANALISTA_N, 
 ac.carga, 
 ROW_NUMBER() OVER (PARTITION BY ac.GRUPO_N ORDER BY ac.carga ASC, ac.ANALISTA_RAW ASC) AS pos, 
 COUNT(*) OVER (PARTITION BY ac.GRUPO_N) AS q_analistas 
 FROM _ativos_carga ac 
), 
_novo_slot AS ( 
 SELECT 
 n.IDWORKFLOW, 
 n.ROUTE_GROUP_RAW, 
 n.ROUTE_GROUP_N, 
 n.rn, 
 ar.q_analistas, 
 CASE WHEN ar.q_analistas = 0 THEN NULL ELSE ((n.rn - 1) % ar.q_analistas) + 1 END AS pos_destino 
 FROM _novos_candidatos n 
 LEFT JOIN (SELECT DISTINCT GRUPO_N, q_analistas FROM _ativos_rank) ar 
 ON ar.GRUPO_N = n.ROUTE_GROUP_N 
), 
_novo_escolha AS ( 
 SELECT 
 ns.IDWORKFLOW, 
 ns.ROUTE_GROUP_RAW, 
 ns.ROUTE_GROUP_N, 
 ar.ANALISTA_RAW AS ANALISTA, 
 ar.ANALISTA_N 
 FROM _novo_slot ns 
 JOIN _ativos_rank ar 
 ON ar.GRUPO_N = ns.ROUTE_GROUP_N 
 AND ar.pos = ns.pos_destino 
 WHERE ns.pos_destino IS NOT NULL 
) 
SELECT 
e.IDWORKFLOW, 
e.ROUTE_GROUP_RAW AS ROUTE_GROUP, 
e.ANALISTA, 
'NOVO' AS FASE, 
'RR_LEASTLOAD_NORM' AS ORIGEM, 
current_timestamp() AS dt_atribuicao, 
current_timestamp() AS dt_ult_atz, 
CASE 
 WHEN ac.carga < s.media 
 THEN CONCAT('Recebeu a mais em NOVO por menor carga: tinha ', CAST(ac.carga AS STRING), ' vs média ', CAST(ROUND(s.media,2) AS STRING)) 
END AS motivo 
FROM _novo_escolha e 
LEFT JOIN _ativos_carga ac 
 ON ac.GRUPO_N = e.ROUTE_GROUP_N 
 AND ac.ANALISTA_N = e.ANALISTA_N 
LEFT JOIN _stats s 
 ON s.GRUPO_N = e.ROUTE_GROUP_N 
WHERE NOT EXISTS ( 
 SELECT 1 
 FROM vw_atribuicao_retorno r 
 WHERE r.IDWORKFLOW = e.IDWORKFLOW 
) 
AND NOT EXISTS ( 
 SELECT 1 
 FROM vw_atribuicao_agente_atual a 
 WHERE a.IDWORKFLOW = e.IDWORKFLOW 
) 
QUALIFY ROW_NUMBER() OVER (PARTITION BY e.IDWORKFLOW ORDER BY e.IDWORKFLOW) = 1; 

MERGE INTO dbw.sbx_bu_gestao_rede.workflow_atribuicao_ouvidoria_nip AS T 
USING vw_atribuicao_novo AS S 
ON T.idworkflow = S.idworkflow 
WHEN NOT MATCHED THEN INSERT ( 
 idworkflow, analista, route_group, fase, origem, dt_atribuicao, dt_ult_atz, motivo 
) VALUES ( 
 S.idworkflow, S.analista, S.route_group, S.fase, S.origem, S.dt_atribuicao, S.dt_ult_atz, S.motivo 
); 

-- ============================================================= 
-- 4) REDISTRIBUIÇÃO 
-- ============================================================= 
CREATE OR REPLACE TEMP VIEW vw_atribuicao_redistribuicao AS 
WITH 
vars AS ( 
 SELECT ( 
 SELECT MAX(DtCarga) 
 FROM dbw.sbx_bu_gestao_rede.dna_ouvidoria_nip 
 ) AS dtcarga_max 
), 
wf_aberto AS ( 
 SELECT D.IDWORKFLOW 
 FROM dbw.tabela.wfworkflow D 
 WHERE TO_DATE(D.DTHRFIM) = DATE '1900-01-01' 
 AND TO_DATE(D.DTHRCANCELAMENTO) = DATE '1900-01-01' 
), 
rg_norm AS ( 
 SELECT 
 IDWORKFLOW, 
 TRANSLATE( 
 UPPER(TRIM(ROUTE_GROUP)), 
 'ÁÀÃÂÉÈÊÍÌÎÓÒÕÔÚÙÛÇ', 
 'AAAAEEEIIIOOOOUUUC' 
 ) AS ROUTE_GROUP_N, 
 ROUTE_GROUP AS ROUTE_GROUP_RAW 
 FROM _rg_all 
), 
wa_norm AS ( 
 SELECT 
 wa.idworkflow, 
 TRANSLATE( 
 UPPER(TRIM(wa.route_group)), 
 'ÁÀÃÂÉÈÊÍÌÎÓÒÕÔÚÙÛÇ', 
 'AAAAEEEIIIOOOOUUUC' 
 ) AS WA_ROUTE_GROUP_N, 
 UPPER(TRIM(wa.analista)) AS WA_ANALISTA, 
 wa.fase AS WA_FASE, 
 wa.origem AS WA_ORIGEM, 
 wa.route_group AS WA_ROUTE_GROUP_RAW 
 FROM dbw.sbx_bu_gestao_rede.workflow_atribuicao_ouvidoria_nip wa 
), 
ativos AS ( 
 SELECT 
 TRANSLATE( 
 UPPER(TRIM(GRUPO)), 
 'ÁÀÃÂÉÈÊÍÌÎÓÒÕÔÚÙÛÇ', 
 'AAAAEEEIIIOOOOUUUC' 
 ) AS GRUPO_N, 
 UPPER(TRIM(ANALISTA)) AS ANALISTA 
 FROM dbw.sbx_bu_gestao_rede.dna_ouvidoria_nip a 
 WHERE a.STATUS = 'Ativo' 
 AND a.DtCarga = (SELECT dtcarga_max FROM vars) 
), 
_carga AS ( 
 SELECT 
 TRANSLATE( 
 UPPER(TRIM(wa.route_group)), 
 'ÁÀÃÂÉÈÊÍÌÎÓÒÕÔÚÙÛÇ', 
 'AAAAEEEIIIOOOOUUUC' 
 ) AS GRUPO_N, 
 UPPER(TRIM(wa.analista)) AS ANALISTA, 
 COUNT(*) AS carga 
 FROM dbw.sbx_bu_gestao_rede.workflow_atribuicao_ouvidoria_nip wa 
 JOIN wf_aberto w ON w.IDWORKFLOW = wa.idworkflow 
 GROUP BY 
 TRANSLATE( 
 UPPER(TRIM(wa.route_group)), 
 'ÁÀÃÂÉÈÊÍÌÎÓÒÕÔÚÙÛÇ', 
 'AAAAEEEIIIOOOOUUUC' 
 ), 
 UPPER(TRIM(wa.analista)) 
), 
ativos_carga AS ( 
 SELECT 
 a.GRUPO_N, 
 a.ANALISTA, 
 COALESCE(c.carga, 0) AS carga 
 FROM ativos a 
 LEFT JOIN _carga c 
 ON c.GRUPO_N = a.GRUPO_N 
 AND c.ANALISTA = a.ANALISTA 
), 
_stats AS ( 
 SELECT GRUPO_N, AVG(carga) AS media 
 FROM ativos_carga 
 GROUP BY GRUPO_N 
),
redist_cands AS ( 
 SELECT DISTINCT 
 wa.idworkflow, 
 rn.ROUTE_GROUP_N, 
 rn.ROUTE_GROUP_RAW, 
 wa.WA_ANALISTA AS ANALISTA_ATUAL, 
 wa.WA_FASE, 
 wa.WA_ORIGEM, 
 wa.WA_ROUTE_GROUP_RAW 
 FROM wa_norm wa 
 JOIN rg_norm rn 
 ON rn.IDWORKFLOW = wa.idworkflow 
 AND rn.ROUTE_GROUP_N = wa.WA_ROUTE_GROUP_N 
 JOIN dbw.sbx_bu_gestao_rede.dna_ouvidoria_nip dn 
 ON TRANSLATE( 
 UPPER(TRIM(dn.GRUPO)), 
 'ÁÀÃÂÉÈÊÍÌÎÓÒÕÔÚÙÛÇ', 
 'AAAAEEEIIIOOOOUUUC' 
 ) = wa.WA_ROUTE_GROUP_N 
 AND UPPER(TRIM(dn.ANALISTA)) = wa.WA_ANALISTA 
 AND dn.STATUS = 'Redistribuir' 
 AND dn.DtCarga = (SELECT dtcarga_max FROM vars) 
 JOIN dbw.tabela.wfworkflow wf 
 ON wf.IDWORKFLOW = wa.idworkflow 
 JOIN _atividade_aberta_corrente_CI cur 
 ON cur.IDWORKFLOW = wa.idworkflow 
 WHERE TO_DATE(wf.DTHRFIM) = DATE '1900-01-01' 
 AND TO_DATE(wf.DTHRCANCELAMENTO) = DATE '1900-01-01' 
 AND cur.grupo_atual = 'GESTÃO DE REDE NACIONAL' 
), 
redist_enum AS ( 
 SELECT 
 rc.*, 
 ROW_NUMBER() OVER (PARTITION BY rc.ROUTE_GROUP_N ORDER BY rc.idworkflow) AS rn 
 FROM redist_cands rc 
), 
ativos_rank_full AS ( 
 SELECT 
 ac.GRUPO_N, 
 ac.ANALISTA, 
 ac.carga, 
 ROW_NUMBER() OVER (PARTITION BY ac.GRUPO_N ORDER BY ac.carga ASC, ac.ANALISTA ASC) AS pos, 
 COUNT(*) OVER (PARTITION BY ac.GRUPO_N) AS q_analistas 
 FROM ativos_carga ac 
),
ativos_pref AS (
  SELECT *
  FROM ativos_rank_full
),
redist_slot AS ( 
 SELECT 
 re.*, 
 ap.q_analistas, 
 CASE 
 WHEN ap.q_analistas = 0 THEN NULL 
 ELSE ((re.rn - 1) % ap.q_analistas) + 1 
 END AS pos_destino 
 FROM redist_enum re 
 LEFT JOIN ( 
 SELECT DISTINCT GRUPO_N, q_analistas 
 FROM ativos_pref 
 ) ap 
 ON ap.GRUPO_N = re.ROUTE_GROUP_N 
), 
redist_escolha AS ( 
 SELECT 
 rs.IDWORKFLOW, 
 rs.ROUTE_GROUP_N, 
 rs.ROUTE_GROUP_RAW, 
 rs.ANALISTA_ATUAL, 
 rs.WA_FASE, 
 rs.WA_ORIGEM, 
 rs.WA_ROUTE_GROUP_RAW, 
 ap.ANALISTA AS NOVO_ANALISTA 
 FROM redist_slot rs 
 JOIN ativos_pref ap 
 ON ap.GRUPO_N = rs.ROUTE_GROUP_N 
 AND ap.pos = rs.pos_destino 
 WHERE rs.pos_destino IS NOT NULL 
) 
SELECT 
e.IDWORKFLOW, 
e.ROUTE_GROUP_RAW AS ROUTE_GROUP, 
e.NOVO_ANALISTA AS ANALISTA, 
'REDISTRIBUICAO' AS FASE, 
'RR_SAFE' AS ORIGEM, 
current_timestamp() AS dt_atribuicao, 
current_timestamp() AS dt_ult_atz, 
CONCAT( 
 'Redistribuição segura: analista atual [', e.ANALISTA_ATUAL, 
 '] marcado como Redistribuir na DNA; fase atual WA = [', e.WA_FASE, 
 ']; origem atual WA = [', COALESCE(e.WA_ORIGEM, 'NULL'), 
 ']; grupo âncora = [', COALESCE(e.WA_ROUTE_GROUP_RAW, 'NULL'), ']' 
) AS motivo, 
'Y' AS ok_to_update 
FROM redist_escolha e 
WHERE UPPER(TRIM(e.NOVO_ANALISTA)) <> UPPER(TRIM(e.ANALISTA_ATUAL)); 

MERGE INTO dbw.sbx_bu_gestao_rede.workflow_atribuicao_ouvidoria_nip AS T 
USING vw_atribuicao_redistribuicao AS S 
ON T.idworkflow = S.idworkflow 
WHEN MATCHED 
 AND S.ok_to_update = 'Y' 
 AND ( 
 UPPER(TRIM(COALESCE(T.analista, ''))) <> UPPER(TRIM(COALESCE(S.analista, ''))) 
 OR UPPER(TRIM(COALESCE(T.route_group, ''))) <> UPPER(TRIM(COALESCE(S.route_group, ''))) 
 ) 
THEN UPDATE SET 
 T.analista = S.analista, 
 T.route_group = S.route_group, 
 T.fase = S.fase, 
 T.origem = S.origem, 
 T.dt_ult_atz = S.dt_ult_atz, 
 T.motivo = S.motivo 
WHEN NOT MATCHED THEN INSERT ( 
 idworkflow, analista, route_group, fase, origem, dt_atribuicao, dt_ult_atz, motivo 
) VALUES ( 
 S.idworkflow, S.analista, S.route_group, S.fase, S.origem, S.dt_atribuicao, S.dt_ult_atz, S.motivo 
);
