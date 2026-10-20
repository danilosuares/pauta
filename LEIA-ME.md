# appsp · home e Pauta

O repositório publica um site estático pelo Cloudflare Pages. A home fica na raiz; o Pauta fica dentro da pasta `pauta/`.

## Endereços

- Home: `/`
- Votação: `/pauta/?v=CODIGO`
- Administração: `/pauta/admin/`
- Apuração pública: `/pauta/apuracao/?v=CODIGO`

A página de votação não inclui navegação nem conteúdo administrativo. A apuração mostra os totais agregados por item e o número de apartamentos que participaram, sem expor a identidade ou os votos individuais de qualquer apartamento.

## Configuração do Supabase

O arquivo `config.js` contém a URL do projeto e a chave pública `anon`/`publishable`. Ela é destinada ao navegador; nunca coloque uma chave `service_role` nesse arquivo.

Para configurar um projeto Supabase novo:

1. Em **Authentication → Users**, crie a conta que será admin root. Não habilite cadastro público de contas de usuário.
2. No **SQL Editor**, execute `schema.sql`.
3. Cadastre o UUID da conta root em `public.root_admins` com `insert into public.root_admins (user_id) values ('UUID_DA_CONTA_ROOT');`.
4. Confirme a URL e a chave pública em `config.js`.

Para atualizar o Supabase existente antes de publicar esta versão, execute uma vez `public_tally_and_closed_votes_migration.sql`. Ela habilita o cadastro de apartamentos no primeiro acesso, cria a apuração agregada pública e impede novos itens em votações encerradas, sem expor os apartamentos.

## Uso

1. Acesse `/pauta/admin/` e entre com uma conta autorizada.
2. Selecione ou crie o condomínio.
3. Crie uma votação, adicione seus itens e compartilhe o link de votação.
4. Moradores cadastram o apartamento e criam o próprio PIN no primeiro acesso.
5. Compartilhe também o link de apuração para que todos acompanhem os resultados.
6. Ao encerrar uma votação, ela não aceita mais votos nem itens novos.

O projeto Supabase deve continuar ativo. Verifique no painel os limites do plano utilizado.
