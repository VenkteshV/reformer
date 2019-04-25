#! /usr/bin/bash
set -e 

######## hardware ########
# devices
devices=0,1,2,3
worker_gpus=`echo "$devices" | awk '{n=split($0,arr,",");print n}'`

######## dataset ########
# language: zh-en or en-zh
s=de
t=en
# dataset
dataset=iwslt14.tokenized.de-en

######## parameters ########
# which hparams 
param=reformer_iwslt_de_en
# defualt is 103k. About 10 epochs for 700w CWMT
max_update=50000
# dynamic hparams, e.g. change the batch size without the register in code, other_hparams='batch_size=2048'
other_hparams=

######## required ########
# tag is the name of your experiments
tag=iwslt_deep_reformer_e256_l7_add_attn_mean_normb_chain2_dropout03
# whether to continue training if experiment is already existed
is_continue=1


# dir of training data
data_dir=../data/data-bin
# dir of models
output_dir=../checkpoints/torch-1.0.1/${tag}

if [ ! -d "$output_dir" ]; then
  mkdir -p ${output_dir}
elif [ ${is_continue} -eq 0 ]; then
  echo -e "\033[31m$output_dir exists!\033[0m"
  exit -1
fi
# save train.sh
cp `pwd`/${BASH_SOURCE[0]} $output_dir

if [ ! -d "$data_dir/$dataset" ]; then
  # start preprocessing
  echo -e "\033[34mpreprocess from ${data_dir%%/data-bin*}/$dataset to $data_dir/$dataset\033[0m"
  python3 -u preprocess.py \
  --source-lang ${s} \
  --target-lang ${t} \
  --trainpref ${data_dir%%/data-bin*}/${dataset}/train \
  --validpref ${data_dir%%/data-bin*}/${dataset}/valid \
  --testpref ${data_dir%%/data-bin*}/${dataset}/test \
  --destdir ${data_dir}/${dataset}
fi

adam_betas="'(0.9, 0.997)'"

cmd="python3 -u train.py
$data_dir/$dataset
-a $param
-s $s
-t $t

--encoder-embed-dim 256
--decoder-embed-dim 256
--decoder-ffn-embed-dim 1024
--decoder-attention-heads 4
--decoder-input-layer add
--decoder-output-layer attn
--scaling mean
--decoder-normalize-before
--decoder-layers 7
--attention-dropout 0
--relu-dropout 0
--dropout 0.3
--layer-chain attn2d:dec+ffn2d+attn2d:enc+ffn2d

--distributed-world-size 1
--model-parallelism-world-size $worker_gpus
--debug

--no-progress-bar
--log-interval 100

--max-update $max_update
--max-tokens 250
--update-freq 16

--criterion label_smoothed_cross_entropy
--label-smoothing 0.1
--weight-decay 0.0001

--lr-scheduler inverse_sqrt
--warmup-updates 8000
--warmup-init-lr 1e-07
--min-lr 1e-09
--lr 0.001

--save-dir $output_dir

--optimizer adam"
cmd=${cmd}" --adam-betas "${adam_betas}
if [ -n "$other_hparams" ]; then
  cmd=${cmd}" "${other_hparams}
fi

echo -e "\033[34mrun command: "${cmd}"\033[0m"
# start training, >> for preserve content that already existed (continue training)
cmd="CUDA_VISIBLE_DEVICES=$devices nohup "${cmd}" >> $output_dir/train.log 2>&1 &"
eval $cmd

# to avoid the latency of write file
sleep 5s
# monitor training log
tail -n `wc -l ${output_dir}/train.log | awk '{print $1+1}'` -f ${output_dir}/train.log
