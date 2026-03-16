-- ============================================================================
-- JURISDOC - Funções e Triggers
-- ============================================================================
-- Funções auxiliares e triggers para automação e integridade
-- ============================================================================

-- ============================================================================
-- FUNÇÃO: Atualizar timestamp de updated_at
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_updated_at_column() IS 'Atualiza automaticamente o campo updated_at';

-- ============================================================================
-- TRIGGERS: Atualizar updated_at automaticamente
-- ============================================================================

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_sectors_updated_at
    BEFORE UPDATE ON sectors
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_automations_updated_at
    BEFORE UPDATE ON automations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_automation_prompts_updated_at
    BEFORE UPDATE ON automation_prompts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_analysis_requests_updated_at
    BEFORE UPDATE ON analysis_requests
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- FUNÇÃO: Registrar auditoria automaticamente
-- ============================================================================

CREATE OR REPLACE FUNCTION audit_log_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID;
    v_old_values JSONB;
    v_new_values JSONB;
BEGIN
    -- Captura o user_id do contexto da sessão (deve ser setado pela aplicação)
    v_user_id := NULLIF(current_setting('app.current_user_id', TRUE), '')::UUID;
    
    IF TG_OP = 'DELETE' THEN
        v_old_values := to_jsonb(OLD);
        v_new_values := NULL;
        
        INSERT INTO audit_logs (user_id, entity_type, entity_id, action, old_values, new_values)
        VALUES (v_user_id, TG_TABLE_NAME, OLD.id, 'delete', v_old_values, v_new_values);
        
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        v_old_values := to_jsonb(OLD);
        v_new_values := to_jsonb(NEW);
        
        INSERT INTO audit_logs (user_id, entity_type, entity_id, action, old_values, new_values)
        VALUES (v_user_id, TG_TABLE_NAME, NEW.id, 'update', v_old_values, v_new_values);
        
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        v_old_values := NULL;
        v_new_values := to_jsonb(NEW);
        
        INSERT INTO audit_logs (user_id, entity_type, entity_id, action, old_values, new_values)
        VALUES (v_user_id, TG_TABLE_NAME, NEW.id, 'create', v_old_values, v_new_values);
        
        RETURN NEW;
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION audit_log_trigger() IS 'Registra automaticamente todas as operações em audit_logs';

-- ============================================================================
-- TRIGGERS: Auditoria automática
-- ============================================================================

CREATE TRIGGER trg_users_audit
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW
    EXECUTE FUNCTION audit_log_trigger();

CREATE TRIGGER trg_sectors_audit
    AFTER INSERT OR UPDATE OR DELETE ON sectors
    FOR EACH ROW
    EXECUTE FUNCTION audit_log_trigger();

CREATE TRIGGER trg_automations_audit
    AFTER INSERT OR UPDATE OR DELETE ON automations
    FOR EACH ROW
    EXECUTE FUNCTION audit_log_trigger();

CREATE TRIGGER trg_automation_prompts_audit
    AFTER INSERT OR UPDATE OR DELETE ON automation_prompts
    FOR EACH ROW
    EXECUTE FUNCTION audit_log_trigger();

CREATE TRIGGER trg_analysis_requests_audit
    AFTER INSERT OR UPDATE OR DELETE ON analysis_requests
    FOR EACH ROW
    EXECUTE FUNCTION audit_log_trigger();

-- ============================================================================
-- FUNÇÃO: Ativar prompt e desativar os demais
-- ============================================================================

CREATE OR REPLACE FUNCTION activate_automation_prompt(p_prompt_id UUID, p_user_id UUID)
RETURNS VOID AS $$
DECLARE
    v_automation_id UUID;
BEGIN
    -- Busca o automation_id do prompt
    SELECT automation_id INTO v_automation_id
    FROM automation_prompts
    WHERE id = p_prompt_id;
    
    IF v_automation_id IS NULL THEN
        RAISE EXCEPTION 'Prompt não encontrado';
    END IF;
    
    -- Seta o contexto do usuário para auditoria
    PERFORM set_config('app.current_user_id', p_user_id::TEXT, TRUE);
    
    -- Desativa todos os prompts da automação
    UPDATE automation_prompts
    SET is_active = FALSE,
        updated_by = p_user_id
    WHERE automation_id = v_automation_id
      AND is_active = TRUE;
    
    -- Ativa o prompt selecionado
    UPDATE automation_prompts
    SET is_active = TRUE,
        updated_by = p_user_id
    WHERE id = p_prompt_id;
    
    -- Registra na auditoria
    INSERT INTO audit_logs (user_id, entity_type, entity_id, action, new_values)
    VALUES (p_user_id, 'automation_prompt', p_prompt_id, 'activate', 
            jsonb_build_object('prompt_id', p_prompt_id, 'automation_id', v_automation_id));
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION activate_automation_prompt IS 'Ativa um prompt e desativa os demais da mesma automação';

-- ============================================================================
-- FUNÇÃO: Criar nova versão de prompt
-- ============================================================================

CREATE OR REPLACE FUNCTION create_new_prompt_version(
    p_automation_id UUID,
    p_title VARCHAR(150),
    p_prompt_text TEXT,
    p_user_id UUID,
    p_activate BOOLEAN DEFAULT FALSE
)
RETURNS UUID AS $$
DECLARE
    v_next_version INTEGER;
    v_new_prompt_id UUID;
BEGIN
    -- Busca a próxima versão
    SELECT COALESCE(MAX(version), 0) + 1 INTO v_next_version
    FROM automation_prompts
    WHERE automation_id = p_automation_id;
    
    -- Seta o contexto do usuário para auditoria
    PERFORM set_config('app.current_user_id', p_user_id::TEXT, TRUE);
    
    -- Cria o novo prompt
    INSERT INTO automation_prompts (
        automation_id, version, title, prompt_text, 
        is_active, created_by, updated_by
    )
    VALUES (
        p_automation_id, v_next_version, p_title, p_prompt_text,
        FALSE, p_user_id, p_user_id
    )
    RETURNING id INTO v_new_prompt_id;
    
    -- Se deve ativar, chama a função de ativação
    IF p_activate THEN
        PERFORM activate_automation_prompt(v_new_prompt_id, p_user_id);
    END IF;
    
    RETURN v_new_prompt_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION create_new_prompt_version IS 'Cria uma nova versão de prompt para uma automação';

-- ============================================================================
-- FUNÇÃO: Obter prompt ativo de uma automação
-- ============================================================================

CREATE OR REPLACE FUNCTION get_active_prompt(p_automation_id UUID)
RETURNS TABLE (
    id UUID,
    version INTEGER,
    title VARCHAR(150),
    prompt_text TEXT,
    created_by UUID,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ap.id,
        ap.version,
        ap.title,
        ap.prompt_text,
        ap.created_by,
        ap.created_at
    FROM automation_prompts ap
    WHERE ap.automation_id = p_automation_id
      AND ap.is_active = TRUE
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_active_prompt IS 'Retorna o prompt ativo de uma automação';

-- ============================================================================
-- FUNÇÃO: Verificar permissão de usuário em setor
-- ============================================================================

CREATE OR REPLACE FUNCTION user_has_sector_access(p_user_id UUID, p_sector_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_has_access BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM user_sectors
        WHERE user_id = p_user_id
          AND sector_id = p_sector_id
    ) INTO v_has_access;
    
    RETURN v_has_access;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION user_has_sector_access IS 'Verifica se um usuário tem acesso a um setor';

-- ============================================================================
-- FUNÇÃO: Obter automações acessíveis por usuário
-- ============================================================================

CREATE OR REPLACE FUNCTION get_user_automations(p_user_id UUID)
RETURNS TABLE (
    automation_id UUID,
    automation_name VARCHAR(150),
    automation_type VARCHAR(50),
    sector_id UUID,
    sector_name VARCHAR(100),
    is_active BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.id,
        a.name,
        a.automation_type,
        s.id,
        s.name,
        a.is_active
    FROM automations a
    INNER JOIN sectors s ON a.sector_id = s.id
    INNER JOIN user_sectors us ON s.id = us.sector_id
    WHERE us.user_id = p_user_id
      AND a.is_active = TRUE
      AND s.is_active = TRUE
    ORDER BY s.name, a.name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_user_automations IS 'Retorna todas as automações acessíveis por um usuário';

-- ============================================================================
-- FUNÇÃO: Registrar evento de execução
-- ============================================================================

CREATE OR REPLACE FUNCTION log_execution_event(
    p_execution_id UUID,
    p_event_type VARCHAR(50),
    p_message TEXT DEFAULT NULL,
    p_payload JSONB DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_event_id UUID;
BEGIN
    INSERT INTO execution_events (execution_id, event_type, message, payload)
    VALUES (p_execution_id, p_event_type, p_message, p_payload)
    RETURNING id INTO v_event_id;
    
    RETURN v_event_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION log_execution_event IS 'Registra um evento de execução';

-- ============================================================================
-- FUNÇÃO: Calcular estatísticas de automação
-- ============================================================================

CREATE OR REPLACE FUNCTION get_automation_stats(
    p_automation_id UUID,
    p_days INTEGER DEFAULT 30
)
RETURNS TABLE (
    total_requests BIGINT,
    total_executions BIGINT,
    successful_executions BIGINT,
    failed_executions BIGINT,
    avg_duration_ms NUMERIC,
    total_tokens_input BIGINT,
    total_tokens_output BIGINT,
    success_rate NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(DISTINCT ar.id)::BIGINT,
        COUNT(DISTINCT ae.id)::BIGINT,
        COUNT(DISTINCT ae.id) FILTER (WHERE ae.success = TRUE)::BIGINT,
        COUNT(DISTINCT ae.id) FILTER (WHERE ae.success = FALSE)::BIGINT,
        ROUND(AVG(ae.duration_ms), 2),
        SUM(ae.tokens_input)::BIGINT,
        SUM(ae.tokens_output)::BIGINT,
        CASE 
            WHEN COUNT(DISTINCT ae.id) > 0 THEN
                ROUND(
                    (COUNT(DISTINCT ae.id) FILTER (WHERE ae.success = TRUE)::NUMERIC / 
                     COUNT(DISTINCT ae.id)::NUMERIC) * 100, 
                    2
                )
            ELSE 0
        END
    FROM analysis_requests ar
    LEFT JOIN analysis_executions ae ON ar.id = ae.request_id
    WHERE ar.automation_id = p_automation_id
      AND ar.created_at > NOW() - (p_days || ' days')::INTERVAL;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_automation_stats IS 'Calcula estatísticas de uma automação em um período';
