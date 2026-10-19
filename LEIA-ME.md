# Pauta — configuração e publicação

O Pauta usa uma página estática no GitHub Pages e o Supabase para armazenar votações, apartamentos e votos. A conexão é automática e a tela de configuração não aparece para moradores. A URL e a chave pública do Supabase ficam no arquivo `config.js`; elas são informações de cliente web. Nunca coloque a chave `service_role` nesse arquivo.

## Configurar o Supabase e o admin root

1. O projeto Supabase `pauta` já está criado. Abra o **SQL Editor** desse projeto.
2. Em **Authentication → Users**, use a conta escolhida como admin root. Não habilite cadastro público de usuários.
3. Cole e execute todo o conteúdo de `schema.sql`. O arquivo configura as tabelas e políticas sem apagar os registros atuais.
4. Copie o UUID da conta root em **Authentication → Users**. No SQL Editor, execute o comando abaixo substituindo o UUID:

   ```sql
   insert into public.root_admins (user_id) values ('UUID_DA_CONTA_ROOT');
   ```

5. Em **Project Settings → API**, copie a **Project URL** e a chave pública **anon** ou **publishable**.
6. Abra `config.js` e preencha `supabaseUrl` e `supabaseAnonKey` com esses valores. Não use `service_role`.
7. Publique `index.html`, `config.js`, `schema.sql` e `LEIA-ME.md` na raiz do repositório GitHub. No GitHub, ative **Settings → Pages** para publicar a branch principal a partir da pasta raiz (`/`).
8. Acesse a URL do site e abra **Administração**. Entre com o e-mail e senha da conta root. O painel root mostra o estado da conexão; somente essa conta pode criar condomínios.
9. Ao criar um condomínio, a conta root também se torna administradora daquele condomínio. Cadastre os demais apartamentos e os administradores necessários usando o fluxo administrativo disponível.

Para trocar o projeto Supabase depois, atualize `config.js` e publique a alteração no GitHub. A chave pública é visível para qualquer visitante, como é esperado em uma aplicação web; as permissões e políticas do banco controlam o acesso. Nunca compartilhe nem publique a chave `service_role`.

## Usar as votações

1. Na aba **Administração**, crie o condomínio e escolha o padrão de identidade: número + bloco ou apenas número.
2. Cadastre os apartamentos com celular de contato e PIN individual. A identidade escolhida é única dentro do condomínio.
3. Crie uma ou mais votações, adicione temas e copie o link direto de cada votação para compartilhar.
4. O morador abre o link, informa a identidade e o PIN e distribui até o limite definido. Votações encerradas continuam disponíveis para consulta dos resultados.

O projeto do Supabase deve permanecer ativo e dentro dos limites do plano escolhido; confira o painel para os limites atuais.

## O que inclui o MVP

- Interface em português, adaptável a celular.
- Vários condomínios, com várias votações e links próprios.
- Identidade por número + bloco ou apenas número, com unicidade dentro do condomínio.
- PIN de acesso individual por apartamento, armazenado como hash.
- Limite de votos por apartamento, um voto por tema e opção de retirar voto enquanto a votação estiver aberta.
- Resultados e ranking compartilhados, com atualização automática.
- Regras SQL e RLS para limitar operações de administração aos administradores autorizados e aplicar a cota de votos no servidor.
