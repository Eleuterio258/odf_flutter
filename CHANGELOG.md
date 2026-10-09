## 0.3.0

- Primeira versão publicada.
- Criação de documentos de texto (ODT) com formatação de caracteres e parágrafos, títulos, listas aninhadas, tabelas com mesclagem, imagens, notas de rodapé, cabeçalho, rodapé, tamanho de página e metadados.
- Criação de planilhas (ODS) com números, moeda, porcentagem, datas, horas, booleanos, fórmulas, formatos numéricos, estilos de célula, mesclagem, notas, larguras e alturas.
- Criação de apresentações (ODP) com títulos, caixas de texto, listas, imagens, formas, fundo e anotações do apresentador.
- Leitura estruturada de ODT, ODS e ODP, inclusive de modelos (.ott, .ots, .otp).
- Preenchimento de modelos com campos `{{...}}`, linhas repetidas e blocos condicionais, preservando o restante do arquivo.
- Conversões: ODT → HTML, ODT ↔ Markdown, planilha ↔ CSV e planilha ↔ JSON.
- Erros claros (`OdfException`) para arquivos inválidos ou protegidos por senha, e limites contra arquivos maliciosos.
