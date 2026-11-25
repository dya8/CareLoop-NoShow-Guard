# CareLoop Clinics – No-Show Guard
 
**Repository:** https://github.com/dya8/CareLoop-NoShow-Guard
 
**Business question:** which appointments are most likely to be missed, why do patients miss them, and what should CareLoop do first?
 
## Summary: one finding per part
 
1. **Data (Part 1):** I started with 1,020 raw bookings. After removing 20 exact duplicates and 10 rows with an unreadable date or missing status, 990 clean appointments remain. Of these, 218 are no-shows (22.0%). Before filling, 17 ages were missing or impossible; they were set to the median of 48.
2. **SQL (Part 2):** the no-show rate rises with lead time. It is 16.2% for bookings made 1–7 days ahead and 60.5% for bookings made 31 or more days ahead. Hadapsar Care Centre (Pune) has the highest rate among large clinics, at 27.3%.
3. **Model (Part 3):** logistic regression scores a cross-validated training ROC-AUC of 0.774 and a test ROC-AUC of 0.789. At a threshold of 0.35 it flags 49 of 198 test bookings and catches 57.1% of the real no-shows.
4. **Notes (Part 4):** Gemini classified 9 non-blank notes (N004 was blank and skipped without an API call) using 12 API calls in total; 2 of the 9 were `forgot_or_no_reminder` (N001, N007), and both belong to appointments with `reminder_sent = No` (2 of 2), while 5 of the 10 notes overall came from appointments where no reminder was sent.
## Recommendation
 
CareLoop should first make sure every booking gets a reminder, and should give extra attention to bookings made more than two weeks ahead. Lead time is the strongest pattern in the data. Bookings made 31 or more days ahead are missed 60.5% of the time, against 16.2% for bookings made within a week, and 296 of the 990 appointments (29.9%) were booked more than 14 days ahead. Reminders show the strongest protective association in the model: holding the other features constant, the odds of a no-show are about 69% lower (odds × 0.31) when a reminder was sent. The call-centre notes point the same way, since both notes classified as "forgot / no reminder" came from appointments where no reminder was sent. In practice, the front desk should run the logistic-regression risk score every evening after reminders go out and phone the bookings scored at 0.35 or above. On the test set that meant about 1 in 4 bookings (49 of 198), and it caught 57% of the patients who would otherwise have left an empty slot. The rest of the call-centre effort should go to the two clinics with the highest rates: Hadapsar (27.3%) and Gomti Nagar (33.3%, but based on only 90 appointments).
 
## Chosen model and threshold
 
- **Model:** logistic regression inside a `StandardScaler` pipeline. Using only the training set, it had the highest 5-fold cross-validated ROC-AUC (0.774). The other candidates were the tuned random forest (0.767, with `max_depth=3` and `n_estimators=200`), the 100-tree random forest (0.747) and the depth-3 tree (0.678). The test set was not used to choose the model.
- **Threshold: 0.35.** I compared thresholds on out-of-fold training probabilities. At 0.35 the scores were precision 0.513, recall 0.467 and F1 0.489, with 154 bookings flagged. At 0.5 they were precision 0.575, recall 0.249 and F1 0.347, with 73 flagged. 0.35 has the higher F1 and nearly double the recall. Recall matters here because a missed warning costs an empty slot, while an extra phone call costs about a minute.
- **One final test evaluation:** ROC-AUC 0.789, precision 0.571, recall 0.571, 49 flagged. Results for every test row are in `test_risk_scores.csv`.
## Limitations
 
1. **Leakage in the cleaning step:** the medians, quartiles and outlier fences were calculated on all 990 rows before the train/test split, so the test rows had a small indirect influence on the cleaned data.
2. **Patients and time:** the same patient can appear in both the training and test sets, and the split is random rather than past-to-future. A real system would be trained on earlier months and used on later ones, so the test scores are probably somewhat optimistic.
3. **Notes and causation:** the 10 notes only illustrate the method and cannot show the real reasons clinic-wide. The reminder effect is an association from observational data, not proof that reminders cause attendance; patients who received reminders may differ in other ways.
## Repository contents
 
| File | Part | What it is |
|---|---|---|
| `data/` | – | The three original CSVs, unchanged |
| `01_ingest_clean.ipynb` | 1 | Ingestion, cleaning, features, API enrichment, SQL generation |
| `rejected_rows.json` | 1 | 32 rows rejected by the `csv`-module parse |
| `appointments_clean.csv` | 1 | 990 × 16 clean table |
| `clinics_enriched.csv` | 1 | 8 clinics + `temp_c` from Open-Meteo |
| `load_data.sql` | 1 → 2 | 998 INSERT statements |
| `02_queries.sql` | 2 | Schema, load checks, duplicate-key error, analysis queries |
| `03_model.ipynb` | 3 | Models, cross-validation, threshold choice, single test evaluation |
| `test_risk_scores.csv` | 3 | 198 test rows: `appointment_id, no_show, risk_prob, flag` |
| `04_genai.ipynb` | 4 | Gemini + Pydantic note analysis (API key not stored) |
| `notes_analysed.csv` | 4 | 10 analysed notes with raw responses |
 
