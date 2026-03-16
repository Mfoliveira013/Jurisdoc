-- ============================================================================
-- JURISDOC - Views e Consultas Úteis
-- ============================================================================
-- Views para facilitar consultas comuns no sistema
-- ============================================================================

-- ============================================================================
-- VIEW: Usuários com seus perfis e setores
-- ============================================================================

CREATE OR REPLACE VIEW vw_users_complete AS
SELECT 
    u.id,
    u.name,
    u.email,
    u.is_active,
    r.name AS role_name,
    r.access_level,
    ARRAY_AGG(DISTINCT s.name ORDER BY s.name) FILTER (WHERE s.name IS NOT NULL) AS sectors,
    ARRAY_AGG(DISTINCT s.id ORDER BY s.name) FILTER (WHERE s.id IS NOT NULL) AS sector_ids,
    u.created_at,
    u.updated_at
FROM users u
INNER JOIN roles r ON u.role_id = r.id
LEFT JOIN user_sectors us ON u.id = us.user_id
LEFT JOIN sectors s ON us.sector_id = s.id
GROUP BY u.id, u.name, u.email, u.is_active, r.name, r.access_level, u.created_at, u.updated_at;

COMMENT ON VIEW vw_users_complete IS 'Visão completa de usuários com perfis e setores';

-- ============================================================================
-- VIEW: Automações com informações completas
-- ============================================================================

CREATE OR REPLACE VIEW vw_automations_complete AS
SELECT 
    a.id,
    a.name,
    a.description,
    a.automation_type,
    a.is_active,
    s.name AS sector_name,
    s.id AS sector_id,
    creator.name AS created_by_name,
    updater.name AS updated_by_name,
    ap.id AS active_prompt_id,
    ap.version AS active_prompt_version,
    ap.title AS active_prompt_title,
    a.created_at,
    a.updated_at
FROM automations a
INNER JOIN sectors s ON a.sector_id = s.id
LEFT JOIN users creator ON a.created_by = creator.id
LEFT JOIN users updater ON a.updated_by = updater.id
LEFT JOIN automation_prompts ap ON a.id = ap.automation_id AND ap.is_active = TRUE;

COMMENT ON VIEW vw_automations_complete IS 'Visão completa de automações com setor e prompt ativo';

-- ============================================================================
-- VIEW: Histórico de prompts por automação
-- ============================================================================

CREATE OR REPLACE VIEW vw_automation_prompts_history AS
SELECT 
    ap.id,
    ap.automation_id,
    a.name AS automation_name,
    ap.version,
    ap.title,
    ap.is_active,
    creator.name AS created_by_name,
    updater.name AS updated_by_name,
    ap.created_at,
    ap.updated_at,
    LENGTH(ap.prompt_text) AS prompt_length
FROM automation_prompts ap
INNER JOIN automations a ON ap.automation_id = a.id
LEFT JOIN users creator ON ap.created_by = creator.id
LEFT JOIN users updater ON ap.updated_by = updater.id
ORDER BY a.name, ap.version DESC;

COMMENT ON VIEW vw_automation_prompts_history IS 'Histórico de versões de prompts por automação';

-- ============================================================================
-- VIEW: Estatísticas de execução por automação
-- ============================================================================

CREATE OR REPLACE VIEW vw_automation_execution_stats AS
SELECT 
    a.id AS automation_id,
    a.name AS automation_name,
    s.name AS sector_name,
    COUNT(DISTINCT ar.id) AS total_requests,
    COUNT(DISTINCT ae.id) AS total_executions,
    COUNT(DISTINCT ae.id) FILTER (WHERE ae.success = TRUE) AS successful_executions,
    COUNT(DISTINCT ae.id) FILTER (WHERE ae.success = FALSE) AS failed_executions,
    ROUND(AVG(ae.duration_ms)) AS avg_duration_ms,
    SUM(ae.tokens_input) AS total_tokens_input,
    SUM(ae.tokens_output) AS total_tokens_output,
    MAX(ae.finished_at) AS last_execution_at
FROM automations a
INNER JOIN sectors s ON a.sector_id = s.id
LEFT JOIN analysis_requests ar ON a.id = ar.automation_id
LEFT JOIN analysis_executions ae ON ar.id = ae.request_id
GROUP BY a.id, a.name, s.name;

COMMENT ON VIEW vw_automation_execution_stats IS 'Estatísticas de execução por automação';

-- ============================================================================
-- VIEW: Últimas solicitações com detalhes
-- ============================================================================

CREATE OR REPLACE VIEW vw_recent_analysis_requests AS
SELECT 
    ar.id,
    ar.external_reference,
    ar.source_system,
    ar.status,
    a.name AS automation_name,
    s.name AS sector_name,
    u.name AS requested_by_name,
    COUNT(ae.id) AS execution_count,
    MAX(ae.finished_at) AS last_execution_at,
    ar.created_at,
    ar.updated_at
FROM analysis_requests ar
INNER JOIN automations a ON ar.automation_id = a.id
INNER JOIN sectors s ON a.sector_id = s.id
LEFT JOIN users u ON ar.requested_by = u.id
LEFT JOIN analysis_executions ae ON ar.id = ae.request_id
GROUP BY ar.id, ar.external_reference, ar.source_system, ar.status, 
         a.name, s.name, u.name, ar.created_at, ar.updated_at
ORDER BY ar.created_at DESC;

COMMENT ON VIEW vw_recent_analysis_requests IS 'Últimas solicitações de análise com detalhes';

-- ============================================================================
-- VIEW: Auditoria com informações legíveis
-- ============================================================================

CREATE OR REPLACE VIEW vw_audit_logs_readable AS
SELECT 
    al.id,
    u.name AS user_name,
    u.email AS user_email,
    al.entity_type,
    al.entity_id,
    al.action,
    al.old_values,
    al.new_values,
    al.created_at
FROM audit_logs al
LEFT JOIN users u ON al.user_id = u.id
ORDER BY al.created_at DESC;

COMMENT ON VIEW vw_audit_logs_readable IS 'Log de auditoria com nomes de usuários';

-- ============================================================================
-- VIEW: Execuções com detalhes completos
-- ============================================================================

CREATE OR REPLACE VIEW vw_executions_complete AS
SELECT 
    ae.id,
    ae.execution_number,
    ae.status,
    ae.success,
    ar.external_reference,
    a.name AS automation_name,
    s.name AS sector_name,
    u.name AS requested_by_name,
    ap.version AS prompt_version,
    ae.provider,
    ae.model_name,
    ae.duration_ms,
    ae.tokens_input,
    ae.tokens_output,
    ae.error_type,
    ae.started_at,
    ae.finished_at,
    ae.created_at
FROM analysis_executions ae
INNER JOIN analysis_requests ar ON ae.request_id = ar.id
INNER JOIN automations a ON ae.automation_id = a.id
INNER JOIN sectors s ON a.sector_id = s.id
LEFT JOIN users u ON ar.requested_by = u.id
LEFT JOIN automation_prompts ap ON ae.prompt_id = ap.id
ORDER BY ae.created_at DESC;

COMMENT ON VIEW vw_executions_complete IS 'Execuções com todos os detalhes relacionados';

-- ============================================================================
-- CONSULTAS ÚTEIS (Exemplos)
-- ============================================================================

-- Buscar usuários de um setor específico
-- SELECT * FROM vw_users_complete WHERE 'Nome do Setor' = ANY(sectors);

-- Buscar automações ativas de um setor
-- SELECT * FROM vw_automations_complete WHERE sector_name = 'Nome do Setor' AND is_active = TRUE;

-- Buscar execuções com falha nas últimas 24 horas
-- SELECT * FROM vw_executions_complete 
-- WHERE success = FALSE 
-- AND created_at > NOW() - INTERVAL '24 hours'
-- ORDER BY created_at DESC;

-- Buscar alterações feitas por um usuário específico
-- SELECT * FROM vw_audit_logs_readable 
-- WHERE user_email = 'usuario@exemplo.com'
-- ORDER BY created_at DESC;

-- Top 10 automações mais utilizadas
-- SELECT automation_name, sector_name, total_requests, successful_executions, failed_executions
-- FROM vw_automation_execution_stats
-- ORDER BY total_requests DESC
-- LIMIT 10;
