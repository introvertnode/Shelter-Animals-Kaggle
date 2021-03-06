library(data.table)
library(Matrix)
library(xgboost)
library(ggplot2)
library(randomForest)

# read data
train <- read.csv("~/projects/kaggle/Shelter Animals/train.csv", stringsAsFactors = F)
test <- read.csv('~/projects/kaggle/Shelter Animals/test.csv', stringsAsFactors = F)
sample <- read.csv("~/projects/kaggle/Shelter Animals/sample_submission.csv")

# remove unimportant columns
train <- train[, -c(1, 5)]
test <- test[, -1]

dt.train <- setDT(read.csv("~/projects/kaggle/Shelter Animals/dt_train")) # original features work best
dt.test <- setDT(read.csv("~/projects/kaggle/Shelter Animals/dt_test"))

# take care of missing values by imputing the age parameter
full_imp <- rbindlist(list(dt.train[, -1, with = F], dt.test))

# impute missing values with linear regresion
imput_age <- lm(age~., data = full_imp)
summary(imput_age)
imp_age <- predict(imput_age, full_imp[which(is.na(age), arr.ind = T), ])
full_imp[is.na(full_imp[, age]), age := .(imp_age)]

#------------------------------------full training -------------------#
# create matrices
to_train <- full_imp[1:nrow(dt.train), ]
to_test <- full_imp[-c(1:nrow(dt.train)), ]
X <- sparse.model.matrix(OutcomeType~.-1, 
                         data = to_train[, OutcomeType := dt.train[, OutcomeType]])

Y <- as.numeric(dt.train[, OutcomeType]) - 1
numclass <- range(Y)[2] + 1

# set the parameter 
params <- list("objective" = "multi:softprob",
               "eta" = .1,
               "lambda" = 0.2,
               "alpha"  = 0.2,
               "max_depth" = 8,
               "eval_metric" = "mlogloss",
               "num_class" = numclass,
               "subsample" = .8)

# cross-validation
nround =200
set.seed(1532)
bst.cv <-  xgb.cv(params = params, data = X, label = Y, nfold = 10, 
                  nround = nround, verbose = T)

# cv error plot
cv_error <- bst.cv$test.mlogloss.mean
tr_error <- bst.cv$train.mlogloss.mean
min <- which.min(cv_error)
print(paste(min, cv_error[min]))

# plot
ggplot(bst.cv, aes(x = c(1: dim(bst.cv)[1])))+
  geom_line(aes(y = train.mlogloss.mean), color = "green")+
  geom_line(aes(y = test.mlogloss.mean), color = "blue")+
  geom_vline(aes(xintercept = min), color = "red")+
  xlab("number of iterations")+
  ylab("mlogloss")

bst <- xgboost(params = params, data = X, label = Y, 
               nround = nround, verbose = T)

# feature importance
imp <- xgb.importance(dimnames(X)[[2]], model = bst)
p_imp <- xgb.plot.importance(imp[1:10])
p_imp

# train model
# apply predictions
mtest <- sparse.model.matrix(~.-1, data = to_test)

preds <- vector("list", length = 100)
for(i in 1:100){
  print(paste('training model:', i))
  model <- xgboost(data = X, label = Y, params = params, nround = min)
  
  print(paste('applying prediction:', i))
  preds[[i]] <- predict(model, newdata = mtest)
}

com_preds <- colMeans(do.call(rbind, preds))
result <- matrix(com_preds,nrow = 11456, ncol = numclass, byrow = T)
result <- data.frame(sample$ID, result)
colnames(result) <- names(sample)
write.csv(result, file = "~/projects/kaggle/Shelter Animals/xgb_avg3.csv", row.names = F)

#------random forest-------------#
set.seed(1532)
rf_models <- vector("list", length = 5)
for(i in 1:5){
  print(paste('training model:', i))
  rf_models[[i]] <- randomForest(OutcomeType~., data = to_train, 
                                 mtry = 4, ntree = 1000, do.trace = T)
}


rf_model <- do.call(randomForest::combine, rf_models)

rf_12 <- randomForest::combine(rf_models[[1]],rf_models[[2]])

predrf <- predict(rf_model, newdata = to_test, type = "prob")
predrf <- data.frame(sample$ID, predrf)
colnames(predrf) <- names(sample)
write.csv(predrf, file = "~/projects/kaggle/Shelter Animals/rf_4ensemble.csv", row.names = F)


ensemble_pred <- result
ensemble_pred <- 0.5*(result+predrf)
write.csv(predrf, file = "~/projects/kaggle/Shelter Animals/rf_xgb_combined.csv", row.names = F)