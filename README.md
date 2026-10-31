# VESTO. — Streetwear Store

Loja virtual de roupas e acessórios, com GitHub Pages (frontend estático) + Supabase (catálogo, login administrativo, estoque e pedidos).

## Funcionalidades
- Catálogo responsivo, filtros e pesquisa; produtos com fotos, preços e promoções.
- Cores, tamanhos e estoque por variação; carrinho persistido localmente.
- Checkout com retirada ou entrega, dados do cliente e observações. **Pagamento manual**, sem Pix/checkout financeiro integrado e sem envio via WhatsApp.
- Pedido salvo no Supabase com número e total calculado no banco, baixa atômica de estoque e proteção contra compras simultâneas acima da disponibilidade.
- Login de administrador via Supabase Auth, cadastro/edição/ocultação de produtos, variações e acompanhamento de pedidos.
- Demo de vitrine quando Supabase ainda não está configurado. **Demo não recebe pedidos nem habilita cadastro administrativo.**

## Configuração do Supabase
1. Crie um projeto em https://supabase.com/dashboard.
2. Abra **SQL Editor**, cole todo o conteúdo de `supabase.sql` e execute **uma vez em um projeto novo**. Esse script cria as tabelas, regras RLS e funções.
3. Abra **Authentication → Users → Add user**, crie seu usuário com e-mail e senha e confirme o e-mail conforme a configuração do projeto. Copie o **UUID** desse usuário.
4. No SQL Editor, execute: `insert into public.admins(user_id) values ('SEU-UUID-AQUI');` substituindo pelo UUID real.
5. Em **Project Settings / Connect / API Keys** (os nomes variam conforme o painel), copie a **Project URL** e uma **publishable key** (ou a chave legada `anon`, se aplicável).
6. Edite o arquivo `config.js` e preencha `supabaseUrl` e `supabasePublishableKey` com esses valores. Não use chave `service_role`, `secret`, JWT de usuário, nem senha de administrador em arquivo público.
7. Publique e abra o site, clique **ADMIN**, faça login, crie os produtos e suas variações.

## Publicação no GitHub Pages
1. Crie um repositório e envie `index.html`, `style.css`, `app.js`, `config.js`, `supabase.sql`, `README.md` e `.nojekyll` à raiz.
2. **Settings → Pages → Build and deployment → Deploy from a branch → main → /(root) → Save**.
3. Visite o link publicado. Atualize o cache com Ctrl+F5 se necessário.
4. Em Supabase **Authentication → URL Configuration**, configure Site URL e Redirect URLs para a URL pública do projeto se usar emails ou recuperação de senha futuramente.

## Uso
1. Administrador: `https://seu-usuario.github.io/seu-repo/#admin`.
2. Cadastre nome, categoria, descrição, preço, URL de imagem HTTPS e variações (`Preto | M | 5`). Cada cor/tamanho é um SKU com quantidade independente.
3. Na loja, clientes escolhem o SKU, quantidade e adicionam à sacola. No checkout escolhem retirada ou entrega. O pedido fica `pendente` até a equipe confirmar.
4. O painel lista dados do cliente e permite atualizar o status. O valor do frete **não** está incluído no total; é combinado manualmente.

## Avisos para uso em produção
- A chave publicável do Supabase pode aparecer no frontend **somente** porque o banco está protegido por RLS. Nunca exponha chave de servidor.
- RLS limita leituras públicas de produtos e restringe pedidos ao admin; a função `place_order` valida e bloqueia o estoque no servidor.
- Pedidos públicos sem login podem receber spam. Antes de abrir para grande público, implemente verificação anti-bot/rate limiting por Edge Function e políticas de privacidade/LGPD; configure contato e política de cancelamento/devolução.
- O estoque é reservado ao cadastrar o pedido; cancelar um pedido no painel **não** repõe automaticamente o estoque. Reponha manualmente na edição de produtos, após verificar o cancelamento.
- Não há upload integrado de imagens: hospede imagens em URLs HTTPS permanentes (por exemplo, Supabase Storage configurado adequadamente).
- Na tela do painel, o total de pedidos mostra até os 300 pedidos mais recentes (não uma soma histórica completa).
- O GitHub Pages é ideal para o **frontend estático**, mas suas condições de uso não o destinam a hospedar um negócio de e-commerce como serviço online. Para operação comercial real, prefira Cloudflare Pages, Netlify ou Vercel e mantenha Supabase no backend.
- A identidade VESTO. e os produtos de demonstração podem ser alterados. Imagens da demo são URLs de terceiros e podem deixar de funcionar; para produção use imagens próprias com licenciamento adequado.

## Estrutura
```
index.html       interface da loja e do painel
style.css        identidade streetwear responsiva
app.js           catálogo, carrinho, pedidos e admin
config.js        URL e chave publicável do Supabase
supabase.sql     banco, RLS e funções seguras
.nojekyll        publicação estática no GitHub Pages
README.md        instruções
```

## Painel separado: VESTO. Manager

Acesse `https://SEU-USUARIO.github.io/SEU-REPOSITORIO/manager/` para utilizar o painel administrativo independente da vitrine. O painel oferece login, inclusão/edição/ocultação de produtos, upload de imagens, preços, variações de tamanho/cor/estoque e acompanhamento dos pedidos. **A loja e o painel usam o mesmo `config.js` e o mesmo Supabase.**

Para habilitar o upload de fotos execute, uma única vez, `manager/storage.sql` no SQL Editor do Supabase **depois** de `supabase.sql`. As imagens desse bucket são públicas para permitir a exibição no catálogo, mas o upload exige autenticação administrativa via políticas RLS. Não inclua chave `service_role` nem chaves secretas no JavaScript. Configure um usuário no Supabase Authentication e insira seu UUID em `public.admins`, conforme instruções acima.

O endereço `/manager/` não é uma proteção de segurança por si só; o controle efetivo é feito por Supabase Auth e pelas políticas RLS do banco e Storage. O painel deve ser usado com HTTPS. Esta versão mantém também o painel antigo em `#admin` por compatibilidade; para usar apenas o novo painel, acesse exclusivamente `/manager/`.

> GitHub Pages é adequado para testes e apresentação do projeto. Os termos do GitHub restringem seu uso como hospedagem gratuita de e-commerce comercial. Para uma loja em produção, utilize hospedagem comercial apropriada para o frontend.
