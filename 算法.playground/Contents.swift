import UIKit

class Solution {
//    ************** 两数之和
    func twoSum(_ nums: [Int], _ target: Int) -> [Int] {
        var numInfo = [Int: Int]()
        for (index, item) in nums.enumerated() {
            let n = target - item
            if let curIndex = numInfo[n] {
                return [curIndex, index]
            }
            numInfo[item] = index
        }
        
        return []
    }
    
//    ************** 回文数
    func isPalindrome(_ x: Int) -> Bool {
        // 将整数转换为字符串
        let str = String(x)
        
        // 初始化双指针
        var left = str.startIndex
        var right = str.index(before: str.endIndex)
        print("111:\(left)",right)
        // 双指针向中间移动
        while left < right {
            // 比较当前左右指针的字符
            if str[left] != str[right] {
                return false
            }
            
            // 移动指针
            left = str.index(after: left)
            right = str.index(before: right)
        }
        
        return true
    }
    
//    字符          数值
//    I             1
//    V             5
//    X             10
//    L             50
//    C             100
//    D             500
//    M             1000
//    ************** 罗马数字转整数
    func romanToInt(_ s: String) -> Int {
        
        let romanMap:[Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000]
        
        let chaArr = Array(s)
        let chaCount = chaArr.count
        var result = 0

        for i in 0..<chaCount {

           let curA = chaArr[i]
           let curV = romanMap[curA]!

           if i < chaCount - 1 {

               let nextA = chaArr[i + 1]
               let nextV = romanMap[nextA]!

               if curV < nextV {
                   result = result - curV
               } else {
                   result = result + curV
               }
           } else {
               result = result + curV
           }
        }
        
        return result
    }
    
//   ************** 最长公共前缀
    // 方案1
    func longestCommonPrefix(_ strs: [String]) -> String {
        
        guard strs.count > 0 else { return "" }
        var prefix = strs[0]
        
        for str in strs {
            while !str.hasPrefix(prefix) {
                prefix.removeLast()
                if prefix.isEmpty { return "" }
            }
        }
        
        return prefix
    }
    
    // 方案2:纵向对比
    func longestCommonPrefix2(_ strs: [String]) -> String {
        // 处理空数组情况
        guard !strs.isEmpty else { return "" }
        
        // 将第一个字符串转为字符数组作为基准
        let firstStr = strs[0]
        let firstChars = Array(firstStr)
        
        // 遍历基准字符串的每个字符位置
        for i in 0..<firstChars.count {
            let currentChar = firstChars[i]
            
            // 检查其他字符串在相同位置
            for j in 1..<strs.count {
                let str = strs[j]
                
                // 如果当前字符串长度不足或字符不匹配
                if i >= str.count || Array(str)[i] != currentChar {
                    return String(firstChars[0..<i])
                }
            }
        }
        
        // 所有字符都匹配，返回整个基准字符串
        return firstStr
    }
}

let solution = Solution()
solution.romanToInt("IV")

