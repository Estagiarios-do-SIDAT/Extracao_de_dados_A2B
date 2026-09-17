USE mdb;
SET NOCOUNT ON;

SELECT
    st.code AS status_code,
    st.sym AS status_nome,
    st.description AS status_descricao,
    st.del AS deletado
FROM dbo.cr_stat AS st
ORDER BY
    st.code,
    st.sym;