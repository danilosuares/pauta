# Pauta — publicação gratuita

O MVP usa uma página estática e Supabase: o site serve a interface; o banco armazena votações, temas e votos. Há uma demonstração local para conhecer a tela, mas os dados só são compartilhados depois da conexão com o Supabase.

## Preparar o banco

1. Crie um projeto novo e vazio no [Supabase](https://supabase.com/).
2. No painel do projeto, abra **SQL Editor**, cole todo o conteúdo de `schema.sql` e execute. Este esquema v2 é para um banco vazio; se você já executou o esquema da versão anterior, crie um novo projeto Supabase para evitar conflito com as tabelas antigas.
3. Em **Authentication → Users**, crie a conta de administrador com e-mail e senha.
4. Em **Project Settings → API**, copie a **Project URL** e a chave pública **anon** ou **publishable**. Não use a chave `service_role` no navegador.

## Publicar o site sem custo

1. Crie um repositório público no GitHub e coloque `index.html` na raiz.
2. No repositório, abra **Settings → Pages** e escolha publicar a branch principal a partir da pasta raiz (`/`). O GitHub Pages oferece publicação gratuita em repositórios públicos no plano GitHub Free. O endereço ficará parecido com `https://seu-usuario.github.io/nome-do-repositorio/`.
3. Abra o endereço publicado, clique **Conectar** e informe a URL e a chave pública do Supabase.
4. Na aba **Administração**, conecte a conta, entre e crie o condomínio. Escolha o padrão de identidade: número + bloco (padrão) ou apenas número.
5. Cadastre os apartamentos, com celular de contato e PIN individual. O par número + bloco (ou o número, conforme o padrão escolhido) precisa ser único naquele condomínio.
6. Crie uma ou mais votações, adicione os temas e copie o link direto de cada votação para compartilhar. Cada votação pode ser encerrada pelo painel; o link continua mostrando os resultados.
7. Cada morador abre o link da votação e informa a identidade do apartamento e o PIN. Celulares ficam como contato cadastrado e não são usados como etapa de verificação.

O projeto do Supabase deve permanecer ativo e dentro dos limites do plano escolhido; consulte o painel de uso para confirmar os limites atuais. A hospedagem do site e o banco são serviços separados.

## O que já está no MVP

- Interface em português, adaptável a celular.
- Condomínios separados, cada um com seu padrão de identidade e vários links de votação.
- Identidade única por número + bloco ou apenas número, definida ao criar o condomínio.
- Número de celular cadastrado para contato administrativo e do apartamento; o acesso à votação usa identidade e PIN individual (sem confirmação por SMS).
- Cada votação pode ser encerrada; o link permanece válido para consulta dos resultados.
- Limite de votos por apartamento e um voto por tema.
- O morador pode retirar um voto e escolher outro enquanto a votação estiver aberta.
- Resultados e ranking compartilhados; a tela atualiza automaticamente a cada 15 segundos.
- O banco guarda PINs com hash e aplica as regras de votação no servidor. As políticas SQL deixam temas/resultados legíveis publicamente e escondem os registros internos de apartamentos e votos.

Os resultados ficam visíveis para qualquer pessoa que tenha o endereço. O app não coleta nome, e-mail ou unidade fora do PIN que o próprio morador fornece na sessão.
