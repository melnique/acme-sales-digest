%dw 2.0

fun round2(n) = round(n * 100) / 100

fun toEur(amountLocal, rate) = round2(amountLocal * rate)

fun rateFor(cur, fxRates) =
    if (cur == "EUR") 1
    else (fxRates[cur] default 0) then (if ($ == 0) 0 else round(1 / $ * 1000000) / 1000000)
