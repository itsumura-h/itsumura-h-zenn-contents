# nim c -r --expandArc:main src/main.nim

# ARC/ORCモードを有効にする
# --mm:arc または --mm:orc をコンパイル時に指定してください


proc main() =
  var rc_examples = "Rc examples"
  block:
    echo "--- rcA is created ---"

    # rc_aを作成。rc_examplesの所有権がrc_aに移る
    var rcA = rc_examples
    echo "Reference Count of rcA: ", rcA

    # この時点でrc_aの参照カウントは1
    block:
      echo "--- rcA is cloned to rcB ---"

      # rc_aをクローンしてrc_bを作成
      var rcB = rcA
      echo "Reference Count of rcB: ", rcB.repr
      echo "Reference Count of rcA: ", rcA

      # rc_aとrc_bは同じデータを指している
      echo "rcA and rcB are equal: ", rcA == rcB

      # 値のメソッドを直接使用
      echo "Length of the value inside rcA: ", rcA.len()
      echo "Value of rcB: ", rcB

      echo "--- rcB is dropped out of scope ---"
    # スコープを抜けるとrc_bは解放される

    echo "Reference Count of rcA: ", rcA

    echo "--- rcA is dropped out of scope ---"
    # スコープを抜けるとrc_aも解放され、参照カウントは0になり、メモリが解放される

  # エラー！rc_examplesはrc_aにムーブされたため、rc_examplesにアクセスできない
  # echo "rc_examples: ", rc_examples  # エラーが発生します
  # TODO: この行をコメント解除してみてください

# メイン関数の呼び出し
main()
