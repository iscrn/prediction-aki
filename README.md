# A Reproducible ETL Approach for Window-based Prediction of Acute Kidney Injury in Critical Care Unit
A guideline to define Acute Kidney Injury patients in Intensive Care Unit of the Beth Israel Deaconess Medical Center in Massachussets, Boston (MIMIC-III clinical database).
Two different predictive models are applied: 
- Support Vector Machines;
- Gradient Boosting Decision Tree.

Models are developed in different tools: KNIME, Weka and Python.
Here we propose the Jupyter Notebooks for the Python implementation. 

## Data collection and features extraction

Data are firstly collected from MIMIC-III database and discretized according to the KDIGO criteria. 
> Any subject satisfying any of the following criteria, then is an AKI patient: 
> - An increase in sCr ≥ 0.3 mg/dL (≥ 26.5 μmol/L) within  48  hours;
> - An increase in sCr ≥ 1.5 times baseline;
> - Urine volume < 0.5 mL/kg/h for 6 hours.

You can find the source code in files [data_extraction.sql](https://github.com/iscrn/prediction-aki/blob/main/data_extraction.sql) and [DCW-features_extraction.sql](https://github.com/iscrn/prediction-aki/blob/main/DCW-features_extraction.sql). Note that some criteria are tested and evaluated in a different tool, KNIME Analytics Platform and the workflow is not available now. 

Regarding the features, more details can be found in the reference paper. 
Only features of interest are extracted: the demographics data, the comorbidities and medications, and the lab and chart-event measurements. 

The labeling of the eligible IDs is done within each defined temporal windows (24, 48, 72, 96, 120, 144 hours after ICU admission). 

## ML implementation
In the following [.ipynb files](https://github.com/iscrn/prediction-aki) you can access to the source code for the implementation of the prediction. 
Notebooks are divided by model (GBDT or SVM) and by category of features. 
In [this notebook](https://github.com/iscrn/prediction-aki/blob/main/Predictions%20with%20the%20best%20features.ipynb) you have the implementation of both predictive models with the best parameters and features obtained in the previous analyses. 

According to the nature of the features, some pre-processing has been done: 
- dummy variables for categorical features (demographics, comorbidities, medications);
- normalization with a min-max scaler (0-1);
- mean imputation for the missing values;

