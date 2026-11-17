# Laufdiagnose

Die Daten stehen in `BuyWheelDB.scanDiagnostics` (letzte fünf Runs) und
`BuyWheelDB.purchaseDiagnostics` (letzte 100 Kaufversuche). Neue Einträge haben
`diagnosticsVersion = 2`. WoW schreibt SavedVariables beim Ausloggen oder Reload.

Alle Zeitangaben unten sind Millisekunden:

| Feld pro Kauf | Bedeutung |
| --- | --- |
| `priceAgeMs` | Preisempfang bis zum Kaufstart |
| `priceReadyMs` | Preisempfang bis zur ersten beobachteten AH-Bereitschaft |
| `readyToClickMs` | Erste beobachtete Bereitschaft bis zum auslösenden Klick |
| `firstClickPriceAgeMs` | Preisempfang bis zum ersten Klick, auch wenn dieser blockiert wurde |
| `priceWheelClicks` | Klicks seit diesem Preisempfang, einschließlich auslösendem Klick |
| `priceBlockedClicks` | Davon blockierte Klicks vor dem Kaufstart |
| `resumeReadyMs` | Kaufende bis zur ersten beobachteten AH-Bereitschaft |
| `resumeSendMs` | Kaufende bis zum Senden der nächsten Scan-Abfrage |
| `resumeReplyMs` | Kaufende bis zur Antwort auf diese Abfrage |

Bereitschaft wird bei bestehenden Pump-Aufrufen, deren 50-ms-Wiederholungen und
Klicks beobachtet. Die Messung ist keine exakte Zeit des serverseitigen Wechsels.
`readyToClickMs` kann auch andere Blockaden enthalten, etwa eine laufende Abfrage;
es ist daher nicht automatisch menschliche Reaktionszeit. Bei erneutem Preisempfang
beginnen die preisbezogenen Messungen neu.

Die bestehenden Zehn-Sekunden-Fenster zählen zusätzlich `wheelClicks` und
`wheelBlocked_<Grund>`. Gründe sind `purchase`, `post`, `bait`, `request`,
`throttle`, `recovery`, `combat`, `hidden` und `noOffer`. Pro blockiertem Klick wird der erste
zutreffende Grund gezählt. Damit werden auch Klicks ohne folgenden Kauf sichtbar.

Es werden keine zusätzlichen AH-Abfragen oder Bereitschafts-Timer erzeugt.

## Wiederanlauf nach Kauf- und Abfragefehlern

Nach einer fehlgeschlagenen Waren-Kaufbestätigung wartet der Scan mindestens
500 ms und prüft anschließend wie bisher die AH-Bereitschaft. Erfolgreiche Käufe
und Preisabbrüche erhalten diese Pause nicht.

Scheitert eine Wiederanlauf-Abfrage, wartet der nächste Versuch 500 ms beim ersten
Fehler und 1000 ms ab dem zweiten Fehler. Die ersten zwei Wiederanlauf-Fehler
zählen nicht für den automatischen Routenwechsel; weitere Fehler durchlaufen die
bisherige Fehlerbehandlung. STOP verwirft den Wiederanlauf-Timer.

`resume_backoff` protokolliert die geplante Pause in `first` und den Anlass in
`second`. `wheelBlocked_recovery` zählt Klicks während dieser Pause. So lässt sich
im nächsten Run prüfen, ob die bisherigen Browse-Fehler und Timeouts zurückgehen.

## Bait-Post bis zur nächsten Kaufmöglichkeit

Die Post-Diagnose unterscheidet jetzt diese Zeitpunkte (Millisekunden ab
bestätigtem Post, keine zusätzlichen AH-Abfragen):

| Feld | Bedeutung |
| --- | --- |
| `resumeReadyMs` | Erste beobachtete AH-Bereitschaft nach dem Post |
| `resumeSendMs` | Erste Abfrage nach dem Post abgesendet |
| `resumeReplyMs` | Antwort auf diese Abfrage empfangen |
| `resumeHasOffer` | Antwort enthielt ein unter den aktuellen Limits kaufbares Angebot |
| `resumeReplyReadyMs` | Erste beobachtete AH-Bereitschaft nach dieser Antwort |
| `buyReadyMs` | AH bereit, Angebot gültig und keine laufende AH-Operation blockiert den Kauf |
| `firstBuyMs` | Tatsächlich erste Kaufanfrage nach dem Post gestartet |
| `buyReadyToClickMs` | Zeit von `buyReadyMs` bis zur ersten Kaufanfrage |

`firstBuyMs` ist kein reines Latenzmaß: Ohne passendes Angebot, während der
Bait-Erneuerung oder ohne weitere Eingabe kann es erheblich später liegen.
Die Felder messen beobachtete Client-Bereitschaft; sie bestimmen nicht exakt
den Zeitpunkt eines internen serverseitigen Zustandswechsels.

`baitContinuedByWheel` zählt im Scan-Fenster Mausrad-Eingaben, die einen
reservierten Bait-Post oder dessen Bestätigung fortsetzen. Das geht auch ohne
Repeat bait. Es wird nicht im selben Schritt zusätzlich gekauft.

## Direkte Kaufquote nach Repeat bait

Bei aktivem Repeat bait + Buy Bait, ausgeschaltetem Leave Bait und Waren kann
zuerst eine direkte Quote ohne Preisabfrage angefordert werden. Dabei sind die
angezeigten Kosten eine Obergrenze, kein empfangener Marktpreis. Es wird pro
bestätigtem Bait-Post höchstens ein solcher Versuch angeboten.

| Feld im Post-Log | Bedeutung |
| --- | --- |
| `fastQuoteQuantity` | Angeforderte feste Menge |
| `fastQuoteReadyMs` | Postbestätigung bis freier AH-Platz für direkte Quote |
| `fastQuoteSendMs` | Postbestätigung bis zur Eingabe, die die Quote anfordert |
| `fastQuoteOutcome` | Ergebnis des Kaufversuchs |
| `fastQuoteFinishedMs` | Postbestätigung bis zum Ende dieses Versuchs |

`offerSource = "post_fast_quote"`, `route = "post_quote"` und `quoteOnly = true`
kennzeichnen diese Kaufversuche. `expectedUnit`/`expectedTotal` sind hier die
angeforderte Preisobergrenze, `quotedUnit`/`quotedTotal` die Serverquote.
Preisdatenalter und Details einer früheren Abfrage werden nicht übernommen.
`postFastQuoteAttempts` zählt die Versuche im Scan-Fenster.

Ohne Eingabe endet das Angebot zwei Sekunden nach Bereitschaft. Ablehnung,
Zeitüberschreitung und Einstellungsänderungen führen zur normalen frischen
Detailabfrage zurück; ein Erfolg setzt mit der normalen Scanroute fort.
`post_fast_quote_ready`, `post_fast_quote_sent`, `post_fast_quote_expired` und
`post_fast_quote_fallback` protokollieren diese Übergänge. Die reservierte Quote
ist keine zusätzliche AH-Abfrage und wird niemals von einem Timer abgesendet.
