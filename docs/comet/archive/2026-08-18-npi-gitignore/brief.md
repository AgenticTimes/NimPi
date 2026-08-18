# NPI GitIgnore — Brief

为 npi 实现 gitignore 匹配语义：解析 .gitignore/.ignore 规则（!取反、/锚定、*、**、目录后缀），沿目录向上累积，接入 grep/find 跳过忽略文件。对齐 pi 的 ignore 库用法。
