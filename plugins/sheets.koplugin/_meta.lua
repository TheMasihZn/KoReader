local _ = require("gettext")
return {
    fullname = _("Sheets"),
    description = _([[View spreadsheets: .csv, .tsv and .xlsx. Edit and save CSV/TSV files, with simple formulas (=SUM(A1:A9), =A1*B2, AVERAGE, MIN, MAX, COUNT).]]),
    app = {
        icon = "column.three",
        order = 26,
    },
}
