-- ============================================================================
-- JURISDOC - Database Schema
-- ============================================================================
-- Sistema de automação com gestão de usuários, setores, prompts versionados
-- e auditoria completa
-- ============================================================================

-- ============================================================================
-- 1. ROLES (Perfis de Acesso)
-- ============================================================================
-- Cada usuário tem um único perfil
-- Exemplos: admin, gestor, operador, visualizador
-- ============================================================================

CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    access_level INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE roles IS 'Perfis de acesso do sistema';
COMMENT ON COLUMN roles.access_level IS 'Nível hierárquico de acesso (maior = mais permissões)';

-- ============================================================================
-- 2. USERS (Usuários)
-- ============================================================================
-- Cada usuário possui um único perfil (role_id)
-- Pode pertencer a múltiplos setores (via user_sectors)
-- ============================================================================

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) NOT NULL,
    email VARCHAR(200) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE users IS 'Usuários do sistema';
COMMENT ON COLUMN users.role_id IS 'Perfil único do usuário';
COMMENT ON COLUMN users.is_active IS 'Indica se o usuário está ativo no sistema';

-- ============================================================================
-- 3. SECTORS (Setores)
-- ============================================================================
-- Setores organizacionais
-- Usuários podem pertencer a múltiplos setores
-- Automações pertencem a um único setor
-- ============================================================================

CREATE TABLE sectors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE sectors IS 'Setores organizacionais';

-- ============================================================================
-- 4. USER_SECTORS (Vínculo Usuário x Setor)
-- ============================================================================
-- Relacionamento N:N entre usuários e setores
-- Um usuário pode pertencer a múltiplos setores
-- ============================================================================

CREATE TABLE user_sectors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sector_id UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, sector_id)
);

COMMENT ON TABLE user_sectors IS 'Vínculo entre usuários e setores (N:N)';

-- ============================================================================
-- 5. AUTOMATIONS (Automações)
-- ============================================================================
-- Cada automação pertence a um único setor
-- Rastreia quem criou e quem alterou por último
-- ============================================================================

CREATE TABLE automations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sector_id UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    automation_type VARCHAR(50) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (sector_id, name)
);

COMMENT ON TABLE automations IS 'Automações do sistema';
COMMENT ON COLUMN automations.sector_id IS 'Setor ao qual a automação pertence (único)';
COMMENT ON COLUMN automations.automation_type IS 'Tipo de automação (ex: análise_documento, classificação, etc)';
COMMENT ON COLUMN automations.created_by IS 'Usuário que criou a automação';
COMMENT ON COLUMN automations.updated_by IS 'Último usuário que alterou a automação';

-- ============================================================================
-- 6. AUTOMATION_PROMPTS (Prompts das Automações)
-- ============================================================================
-- Versionamento de prompts
-- Cada automação tem um único prompt ativo
-- Mantém histórico completo de versões
-- Rastreia quem criou e alterou cada versão
-- ============================================================================

CREATE TABLE automation_prompts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    automation_id UUID NOT NULL REFERENCES automations(id) ON DELETE CASCADE,
    version INTEGER NOT NULL,
    title VARCHAR(150),
    prompt_text TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT FALSE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (automation_id, version)
);

COMMENT ON TABLE automation_prompts IS 'Prompts versionados das automações';
COMMENT ON COLUMN automation_prompts.version IS 'Número da versão do prompt';
COMMENT ON COLUMN automation_prompts.is_active IS 'Indica se este é o prompt ativo (apenas um por automação)';
COMMENT ON COLUMN automation_prompts.created_by IS 'Usuário que criou esta versão';
COMMENT ON COLUMN automation_prompts.updated_by IS 'Usuário que alterou esta versão';

-- Índice parcial: garante que apenas um prompt por automação esteja ativo
CREATE UNIQUE INDEX ux_automation_prompts_one_active
ON automation_prompts (automation_id)
WHERE is_active = TRUE;

COMMENT ON INDEX ux_automation_prompts_one_active IS 'Garante que apenas um prompt por automação esteja ativo';

-- ============================================================================
-- 7. ANALYSIS_REQUESTS (Solicitações de Análise)
-- ============================================================================
-- Representa o pedido de execução de uma automação
-- ============================================================================

CREATE TABLE analysis_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    automation_id UUID NOT NULL REFERENCES automations(id) ON DELETE CASCADE,
    requested_by UUID REFERENCES users(id) ON DELETE SET NULL,
    external_reference VARCHAR(150),
    source_system VARCHAR(100),
    input_hash VARCHAR(64),
    input_metadata JSONB,
    status VARCHAR(30) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE analysis_requests IS 'Solicitações de execução de automações';
COMMENT ON COLUMN analysis_requests.requested_by IS 'Usuário que solicitou a análise';
COMMENT ON COLUMN analysis_requests.external_reference IS 'Referência externa (ex: número do processo)';
COMMENT ON COLUMN analysis_requests.source_system IS 'Sistema de origem da solicitação';
COMMENT ON COLUMN analysis_requests.input_hash IS 'Hash do input para evitar duplicações';
COMMENT ON COLUMN analysis_requests.input_metadata IS 'Metadados do input em formato JSON';
COMMENT ON COLUMN analysis_requests.status IS 'Status: pending, processing, completed, failed, cancelled';

-- ============================================================================
-- 8. ANALYSIS_EXECUTIONS (Execuções da Análise)
-- ============================================================================
-- Histórico técnico de execução da IA
-- Rastreia modelo usado, tokens consumidos, tempo de execução, etc
-- ============================================================================

CREATE TABLE analysis_executions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID NOT NULL REFERENCES analysis_requests(id) ON DELETE CASCADE,
    automation_id UUID NOT NULL REFERENCES automations(id) ON DELETE CASCADE,
    prompt_id UUID REFERENCES automation_prompts(id) ON DELETE SET NULL,
    
    execution_number INTEGER NOT NULL DEFAULT 1,
    provider VARCHAR(100),
    model_name VARCHAR(100),
    model_version VARCHAR(50),
    
    status VARCHAR(30) NOT NULL DEFAULT 'queued',
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    duration_ms INTEGER,
    
    tokens_input INTEGER,
    tokens_output INTEGER,
    
    success BOOLEAN NOT NULL DEFAULT FALSE,
    error_type VARCHAR(100),
    error_message TEXT,
    
    response_summary TEXT,
    response_metadata JSONB,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE analysis_executions IS 'Histórico de execuções das análises';
COMMENT ON COLUMN analysis_executions.request_id IS 'Solicitação que originou esta execução';
COMMENT ON COLUMN analysis_executions.prompt_id IS 'Versão do prompt utilizada nesta execução';
COMMENT ON COLUMN analysis_executions.execution_number IS 'Número da tentativa (para retries)';
COMMENT ON COLUMN analysis_executions.provider IS 'Provedor da IA (ex: OpenAI, Anthropic, etc)';
COMMENT ON COLUMN analysis_executions.model_name IS 'Nome do modelo (ex: gpt-4, claude-3, etc)';
COMMENT ON COLUMN analysis_executions.duration_ms IS 'Duração da execução em milissegundos';
COMMENT ON COLUMN analysis_executions.tokens_input IS 'Tokens consumidos no input';
COMMENT ON COLUMN analysis_executions.tokens_output IS 'Tokens gerados no output';
COMMENT ON COLUMN analysis_executions.status IS 'Status: queued, running, completed, failed, timeout';

-- ============================================================================
-- 9. EXECUTION_EVENTS (Eventos da Execução)
-- ============================================================================
-- Log detalhado de eventos durante a execução
-- ============================================================================

CREATE TABLE execution_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    execution_id UUID NOT NULL REFERENCES analysis_executions(id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL,
    message TEXT,
    payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE execution_events IS 'Log detalhado de eventos das execuções';
COMMENT ON COLUMN execution_events.event_type IS 'Tipo: queued, started, sent_to_ai, response_received, completed, failed, retried';
COMMENT ON COLUMN execution_events.payload IS 'Dados adicionais do evento em formato JSON';

-- ============================================================================
-- 10. AUDIT_LOGS (Auditoria)
-- ============================================================================
-- Registro completo de todas as alterações no sistema
-- Rastreia quem fez o quê, quando e quais valores foram alterados
-- ============================================================================

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID NOT NULL,
    action VARCHAR(50) NOT NULL,
    old_values JSONB,
    new_values JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE audit_logs IS 'Log de auditoria de todas as operações do sistema';
COMMENT ON COLUMN audit_logs.user_id IS 'Usuário que realizou a ação';
COMMENT ON COLUMN audit_logs.entity_type IS 'Tipo: user, sector, automation, automation_prompt, analysis_request';
COMMENT ON COLUMN audit_logs.entity_id IS 'ID da entidade afetada';
COMMENT ON COLUMN audit_logs.action IS 'Ação: create, update, delete, activate, deactivate';
COMMENT ON COLUMN audit_logs.old_values IS 'Valores anteriores em formato JSON';
COMMENT ON COLUMN audit_logs.new_values IS 'Novos valores em formato JSON';

-- ============================================================================
-- ÍNDICES PARA PERFORMANCE
-- ============================================================================

-- Users
CREATE INDEX idx_users_role_id ON users(role_id);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_is_active ON users(is_active) WHERE is_active = TRUE;

-- User Sectors
CREATE INDEX idx_user_sectors_user_id ON user_sectors(user_id);
CREATE INDEX idx_user_sectors_sector_id ON user_sectors(sector_id);

-- Automations
CREATE INDEX idx_automations_sector_id ON automations(sector_id);
CREATE INDEX idx_automations_created_by ON automations(created_by);
CREATE INDEX idx_automations_is_active ON automations(is_active) WHERE is_active = TRUE;

-- Automation Prompts
CREATE INDEX idx_automation_prompts_automation_id ON automation_prompts(automation_id);
CREATE INDEX idx_automation_prompts_created_by ON automation_prompts(created_by);
CREATE INDEX idx_automation_prompts_is_active ON automation_prompts(is_active) WHERE is_active = TRUE;

-- Analysis Requests
CREATE INDEX idx_analysis_requests_automation_id ON analysis_requests(automation_id);
CREATE INDEX idx_analysis_requests_requested_by ON analysis_requests(requested_by);
CREATE INDEX idx_analysis_requests_status ON analysis_requests(status);
CREATE INDEX idx_analysis_requests_created_at ON analysis_requests(created_at DESC);
CREATE INDEX idx_analysis_requests_input_hash ON analysis_requests(input_hash);

-- Analysis Executions
CREATE INDEX idx_analysis_executions_request_id ON analysis_executions(request_id);
CREATE INDEX idx_analysis_executions_automation_id ON analysis_executions(automation_id);
CREATE INDEX idx_analysis_executions_prompt_id ON analysis_executions(prompt_id);
CREATE INDEX idx_analysis_executions_status ON analysis_executions(status);
CREATE INDEX idx_analysis_executions_created_at ON analysis_executions(created_at DESC);

-- Execution Events
CREATE INDEX idx_execution_events_execution_id ON execution_events(execution_id);
CREATE INDEX idx_execution_events_event_type ON execution_events(event_type);
CREATE INDEX idx_execution_events_created_at ON execution_events(created_at DESC);

-- Audit Logs
CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_entity_type_id ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);

-- ============================================================================
-- DADOS INICIAIS (SEED DATA)
-- ============================================================================

-- Perfis padrão
INSERT INTO roles (name, description, access_level) VALUES
    ('admin', 'Administrador do sistema com acesso total', 100),
    ('gestor', 'Gestor com permissões de gerenciamento', 75),
    ('operador', 'Operador com permissões de execução', 50),
    ('visualizador', 'Visualizador com permissões somente leitura', 25);

-- ============================================================================
-- FIM DO SCHEMA
-- ============================================================================
