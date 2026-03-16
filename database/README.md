# Jurisdoc - Estrutura do Banco de Dados

Sistema de automação com gestão de usuários, setores, prompts versionados e auditoria completa.

## 📋 Visão Geral

Este banco de dados foi projetado seguindo as seguintes regras de negócio:

- ✅ Usuário tem um **único perfil** (role)
- ✅ Usuário pode pertencer a **múltiplos setores**
- ✅ Automação pertence a um **único setor**
- ✅ Cada automação tem um **único prompt ativo**
- ✅ **Auditoria completa** de todas as operações

## 🗂️ Estrutura de Arquivos

```
database/
├── schema.sql      # Schema completo com todas as tabelas e índices
├── views.sql       # Views para consultas comuns
├── functions.sql   # Funções e triggers auxiliares
└── README.md       # Esta documentação
```

## 📊 Tabelas Principais

### 1. Acesso e Organização

| Tabela | Descrição |
|--------|-----------|
| `roles` | Perfis de acesso (admin, gestor, operador, visualizador) |
| `users` | Usuários do sistema (cada um com um único perfil) |
| `sectors` | Setores organizacionais |
| `user_sectors` | Vínculo N:N entre usuários e setores |

### 2. Automações

| Tabela | Descrição |
|--------|-----------|
| `automations` | Automações do sistema (cada uma pertence a um setor) |
| `automation_prompts` | Prompts versionados (um ativo por automação) |

### 3. Histórico Operacional

| Tabela | Descrição |
|--------|-----------|
| `analysis_requests` | Solicitações de execução de automações |
| `analysis_executions` | Histórico técnico de execuções (modelo, tokens, tempo) |
| `execution_events` | Log detalhado de eventos durante execuções |

### 4. Auditoria

| Tabela | Descrição |
|--------|-----------|
| `audit_logs` | Registro completo de todas as alterações no sistema |

## 🔗 Relacionamentos

```
roles
 └── users (1:N)

users
 ├── user_sectors (N:N com sectors)
 ├── automations.created_by
 ├── automations.updated_by
 ├── automation_prompts.created_by
 ├── automation_prompts.updated_by
 ├── analysis_requests.requested_by
 └── audit_logs.user_id

sectors
 ├── user_sectors (N:N com users)
 └── automations (1:N)

automations
 ├── automation_prompts (1:N)
 ├── analysis_requests (1:N)
 └── analysis_executions (1:N)

automation_prompts
 └── analysis_executions (1:N)

analysis_requests
 └── analysis_executions (1:N)

analysis_executions
 └── execution_events (1:N)
```

## 🚀 Instalação

### 1. Criar o banco de dados

```bash
createdb jurisdoc
```

### 2. Executar os scripts na ordem

```bash
psql -d jurisdoc -f database/schema.sql
psql -d jurisdoc -f database/views.sql
psql -d jurisdoc -f database/functions.sql
```

## 📖 Views Disponíveis

### `vw_users_complete`
Usuários com perfis e lista de setores

```sql
SELECT * FROM vw_users_complete WHERE is_active = TRUE;
```

### `vw_automations_complete`
Automações com setor e prompt ativo

```sql
SELECT * FROM vw_automations_complete WHERE sector_name = 'Jurídico';
```

### `vw_automation_execution_stats`
Estatísticas de execução por automação

```sql
SELECT * FROM vw_automation_execution_stats 
ORDER BY total_requests DESC;
```

### `vw_recent_analysis_requests`
Últimas solicitações com detalhes

```sql
SELECT * FROM vw_recent_analysis_requests 
WHERE created_at > NOW() - INTERVAL '7 days';
```

### `vw_audit_logs_readable`
Log de auditoria com nomes de usuários

```sql
SELECT * FROM vw_audit_logs_readable 
WHERE user_email = 'usuario@exemplo.com'
ORDER BY created_at DESC;
```

## 🔧 Funções Úteis

### Criar nova versão de prompt

```sql
SELECT create_new_prompt_version(
    p_automation_id := 'uuid-da-automacao',
    p_title := 'Versão 2.0 - Melhorias',
    p_prompt_text := 'Texto do novo prompt...',
    p_user_id := 'uuid-do-usuario',
    p_activate := TRUE  -- Ativa automaticamente
);
```

### Ativar um prompt existente

```sql
SELECT activate_automation_prompt(
    p_prompt_id := 'uuid-do-prompt',
    p_user_id := 'uuid-do-usuario'
);
```

### Obter prompt ativo

```sql
SELECT * FROM get_active_prompt('uuid-da-automacao');
```

### Verificar acesso de usuário a setor

```sql
SELECT user_has_sector_access(
    p_user_id := 'uuid-do-usuario',
    p_sector_id := 'uuid-do-setor'
);
```

### Obter automações acessíveis por usuário

```sql
SELECT * FROM get_user_automations('uuid-do-usuario');
```

### Obter estatísticas de automação

```sql
SELECT * FROM get_automation_stats(
    p_automation_id := 'uuid-da-automacao',
    p_days := 30  -- Últimos 30 dias
);
```

### Registrar evento de execução

```sql
SELECT log_execution_event(
    p_execution_id := 'uuid-da-execucao',
    p_event_type := 'sent_to_ai',
    p_message := 'Enviado para processamento',
    p_payload := '{"model": "gpt-4", "temperature": 0.7}'::jsonb
);
```

## 🔐 Auditoria Automática

O sistema possui triggers que registram automaticamente todas as operações em `audit_logs`:

- **INSERT**: Registra criação de novos registros
- **UPDATE**: Registra valores antigos e novos
- **DELETE**: Registra valores deletados

### Configurar usuário da sessão

Para que a auditoria capture o usuário correto, configure no início da sessão:

```sql
SET app.current_user_id = 'uuid-do-usuario';
```

## 🎯 Garantias de Integridade

### Único prompt ativo por automação

```sql
CREATE UNIQUE INDEX ux_automation_prompts_one_active
ON automation_prompts (automation_id)
WHERE is_active = TRUE;
```

Este índice parcial garante que apenas um prompt por automação possa estar ativo.

### Unique constraints

- `roles.name` - Nome do perfil único
- `users.email` - Email único
- `sectors.name` - Nome do setor único
- `automations(sector_id, name)` - Nome único dentro do setor
- `automation_prompts(automation_id, version)` - Versão única por automação
- `user_sectors(user_id, sector_id)` - Vínculo único

## 📈 Índices de Performance

Todos os campos frequentemente consultados possuem índices:

- Foreign keys (user_id, sector_id, automation_id, etc)
- Campos de status e flags booleanas
- Campos de data (created_at, updated_at)
- Campos de busca (email, input_hash)

## 💡 Exemplos de Uso

### Criar um novo usuário com setores

```sql
-- 1. Criar usuário
INSERT INTO users (name, email, password_hash, role_id)
VALUES (
    'João Silva',
    'joao.silva@exemplo.com',
    'hash_da_senha',
    (SELECT id FROM roles WHERE name = 'operador')
)
RETURNING id;

-- 2. Vincular a setores
INSERT INTO user_sectors (user_id, sector_id)
VALUES 
    ('uuid-do-usuario', (SELECT id FROM sectors WHERE name = 'Jurídico')),
    ('uuid-do-usuario', (SELECT id FROM sectors WHERE name = 'Compliance'));
```

### Criar automação com prompt inicial

```sql
-- 1. Criar automação
INSERT INTO automations (sector_id, name, description, automation_type, created_by)
VALUES (
    (SELECT id FROM sectors WHERE name = 'Jurídico'),
    'Análise de Contratos',
    'Análise automática de cláusulas contratuais',
    'analise_documento',
    'uuid-do-usuario'
)
RETURNING id;

-- 2. Criar prompt inicial (já ativo)
SELECT create_new_prompt_version(
    p_automation_id := 'uuid-da-automacao',
    p_title := 'Versão 1.0 - Inicial',
    p_prompt_text := 'Analise o contrato e identifique...',
    p_user_id := 'uuid-do-usuario',
    p_activate := TRUE
);
```

### Executar uma análise

```sql
-- 1. Criar solicitação
INSERT INTO analysis_requests (
    automation_id, 
    requested_by, 
    external_reference,
    source_system,
    input_metadata
)
VALUES (
    'uuid-da-automacao',
    'uuid-do-usuario',
    'PROC-2024-001',
    'Sistema Judicial',
    '{"tipo": "contrato", "partes": ["A", "B"]}'::jsonb
)
RETURNING id;

-- 2. Criar execução
INSERT INTO analysis_executions (
    request_id,
    automation_id,
    prompt_id,
    provider,
    model_name,
    status
)
VALUES (
    'uuid-da-request',
    'uuid-da-automacao',
    (SELECT id FROM automation_prompts WHERE automation_id = 'uuid-da-automacao' AND is_active = TRUE),
    'OpenAI',
    'gpt-4',
    'queued'
)
RETURNING id;

-- 3. Registrar eventos
SELECT log_execution_event('uuid-da-execucao', 'queued', 'Execução enfileirada');
SELECT log_execution_event('uuid-da-execucao', 'started', 'Execução iniciada');
SELECT log_execution_event('uuid-da-execucao', 'sent_to_ai', 'Enviado para IA');
```

## 🔍 Consultas Comuns

### Buscar execuções com falha

```sql
SELECT * FROM vw_executions_complete 
WHERE success = FALSE 
AND created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC;
```

### Top 10 automações mais utilizadas

```sql
SELECT automation_name, sector_name, total_requests, success_rate
FROM vw_automation_execution_stats
ORDER BY total_requests DESC
LIMIT 10;
```

### Histórico de alterações de um prompt

```sql
SELECT * FROM vw_audit_logs_readable
WHERE entity_type = 'automation_prompt'
AND entity_id = 'uuid-do-prompt'
ORDER BY created_at DESC;
```

### Usuários de um setor específico

```sql
SELECT * FROM vw_users_complete 
WHERE 'Jurídico' = ANY(sectors)
AND is_active = TRUE;
```

## 📝 Notas Importantes

1. **Perfil único**: Cada usuário tem apenas um perfil em `users.role_id`
2. **Múltiplos setores**: Use `user_sectors` para vincular usuários a vários setores
3. **Prompt ativo**: O índice parcial garante apenas um prompt ativo por automação
4. **Auditoria**: Configure `app.current_user_id` para rastreamento correto
5. **Versionamento**: Sempre use `create_new_prompt_version()` para criar novos prompts
6. **Soft delete**: Use `is_active = FALSE` ao invés de DELETE quando apropriado

## 🛠️ Manutenção

### Limpar logs antigos

```sql
-- Deletar eventos de execução com mais de 90 dias
DELETE FROM execution_events 
WHERE created_at < NOW() - INTERVAL '90 days';

-- Deletar logs de auditoria com mais de 1 ano
DELETE FROM audit_logs 
WHERE created_at < NOW() - INTERVAL '1 year';
```

### Verificar integridade

```sql
-- Verificar automações sem prompt ativo
SELECT a.id, a.name 
FROM automations a
LEFT JOIN automation_prompts ap ON a.id = ap.automation_id AND ap.is_active = TRUE
WHERE ap.id IS NULL
AND a.is_active = TRUE;

-- Verificar usuários sem setores
SELECT u.id, u.name, u.email
FROM users u
LEFT JOIN user_sectors us ON u.id = us.user_id
WHERE us.id IS NULL
AND u.is_active = TRUE;
```

## 📞 Suporte

Para dúvidas ou sugestões sobre a estrutura do banco de dados, consulte a documentação do projeto.
