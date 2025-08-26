import UIKit

public class ListNode {
    public var val: Int
    public var next: ListNode?
    public init() { self.val = 0; self.next = nil; }
    public init(_ val: Int) { self.val = val; self.next = nil; }
    public init(_ val: Int, _ next: ListNode?) { self.val = val; self.next = next; }
}

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
    
//    ************** 是否为 回文数（双指针法）
    func isPalindrome2(_ x: Int) -> Bool {
        let str = String(x)
        let chars = Array(str)
        var left = 0
        var right = chars.count - 1
        
        for char in chars {
            if left < right, left < chars.count - 1, right > 0 {
                if chars[left] != chars[right] {
                    return false
                }
                left = left + 1
                right = right - 1
            }
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
    
//    ************** 两数相加（链表）
    func addTwoNumbers(_ l1: ListNode?, _ l2: ListNode?) -> ListNode? {
        let dummy = ListNode(0) // 哑节点简化操作
        var current: ListNode? = dummy // 指针指向dummy
        var p = l1
        var q = l2
        var carry = 0 // 进位值
        
        while p != nil || q != nil || carry != 0 {
            let val1 = p?.val ?? 0
            let val2 = q?.val ?? 0
            let sum = val1 + val2 + carry
            
            // 计算当前位的值和进位
            carry = sum / 10
            let digit = sum % 10
            
            // 创建新节点并链接
            current?.next = ListNode(digit)
            current = current?.next
            
            // 移动原链表指针
            p = p?.next
            q = q?.next
        }
        
        return dummy.next // 哑节点 (dummy) 的 next 指针始终指向实际创建的第一个有效节点
    }
    
//   *************** 无重复字符的最长子串
    func lengthOfLongestSubstring(_ s: String) -> Int {
        var charMap: [Character: Int] = [:]
        var maxLength = 0
        var start = 0
        let chars = Array(s)
        
        for (index, char) in chars.enumerated() {
            if let preIndex = charMap[char], preIndex >= start {
                start = preIndex + 1
            }
            
            charMap[char] = index
            
            let len = index - start + 1
            maxLength = max(maxLength, len)
        }
        
        return maxLength
    }
   
//    ************* 最长回文子串
//    示例 1：
//
//    输入：s = "babad"
//    输出："bab"
//    解释："aba" 同样是符合题意的答案。
//    示例 2：
//
//    输入：s = "cbbd"
//    输出："bb"
    func longestPalindrome(_ s: String) -> String {
        
        let chars = Array(s)
        var left = 0
        var right = chars.count - 1
        var resultChars: [Character] = []
        var tempChars: [Character] = []
        
        while left < right, left < chars.count - 1, right > 0 {
            if chars[left] == chars[right] {
                let midIndex = tempChars.count / 2
                tempChars.insert(chars[left], at: midIndex)
                tempChars.insert(chars[right], at: midIndex + 1)
            } else {
                if tempChars.count > resultChars.count {
                    resultChars = tempChars
                }
            }
            
            left = left + 1
            right = right - 1
            
            if chars.count % 2 > 0, left == chars.count / 2 {
                tempChars.insert(chars[left], at: left)
            }
        }
        
        if tempChars.count > resultChars.count {
            resultChars = tempChars
        }
        
        return String(resultChars)
    }
    
//   ************* 合并两个有序链表
    // 将两个升序链表合并为一个新的 升序 链表并返回。新链表是通过拼接给定的两个链表的所有节点组成的。
    func mergeTwoLists(_ list1: ListNode?, _ list2: ListNode?) -> ListNode? {
        var dummy = ListNode(0)
        var p = list1
        var q = list2
        var cur = dummy
        
        while p != nil, q != nil {
            if p!.val < q!.val {
                cur.next = p
                p = p?.next
            } else {
                cur.next = q
                q = q?.next
            }
            
            cur = cur.next!
        }
        
        let temp = p != nil ? p : q
        cur.next = temp
        
        return dummy.next
    }
    
//    *************** 有效的括号
    // 给定一个只包括 '('，')'，'{'，'}'，'['，']' 的字符串 s ，判断字符串是否有效。
    func isValid(_ s: String) -> Bool {
        // 创建映射关系：右括号 -> 对应的左括号
          let mapping: [Character: Character] = [")": "(", "]": "[", "}": "{"]
          var stack = [Character]()  // 使用数组作为栈
          
          for char in s {
              if let left = mapping[char] {
                  // 当前字符是右括号
                  // 使用 `stack.removeLast()` 有两个作用：
                  // - 获取栈顶元素（与 `stack.last` 相同）
                  // - 同时将其从栈中移除（弹出）
                  // - 类似消消乐，遇到匹配的就把匹配到的左括号删除
                  if stack.isEmpty || stack.removeLast() != left {
                      return false
                  }
              } else {
                  // 当前字符是左括号
                  stack.append(char)
              }
          }
          
          // 所有括号匹配当且仅当栈为空（消消乐）
          return stack.isEmpty
    }
    
//  ******************* 移除元素: 快慢指针
    // 给你一个数组 nums 和一个值 val，你需要 原地 移除所有数值等于 val 的元素。元素的顺序可能发生改变。然后返回 nums 中与 val 不同的元素的数量。
    // 原地移除 指的是：在不分配新数组或新的主要数据结构的情况下，直接在给定的原始数组（或数据结构）的内存空间内重新组织元素，以达到"移除"某些元素的效果。
    func removeElement(_ nums: inout [Int], _ val: Int) -> Int {
        var slow = 0
        // 使用索引而不是直接遍历值
        for fast in 0..<nums.count {
            if nums[fast] != val {
                nums[slow] = nums[fast]  // 明确操作索引位置
                slow += 1
            }
        }
        return slow
    }
    
//   ********************* 整数反转：数学法
    func reverse(_ x: Int) -> Int {
        var result = 0
        var num = x
        while num != 0 {
            let digit = num % 10
            num = num / 10
            //当result大于maxLimit / 10时，乘以 10 后一定会溢出
            if result > Int32.max / 10 || (result == Int32.max && digit > 7) {
                return 0
            }
            
            if result < Int32.min / 10 || (result == Int32.min && digit < -8) {
                return 0
            }
            
            result = result * 10 + digit
        }
        
        return result
    }
//   **************** 盛最多水的容器: 双指针法，移动较短的那条线
    // 给定一个长度为 n 的整数数组 height 。有 n 条垂线，第 i 条线的两个端点是 (i, 0) 和 (i, height[i]) 。
    // 找出其中的两条线，使得它们与 x 轴共同构成的容器可以容纳最多的水。
    // 返回容器可以储存的最大水量。
    func maxArea(_ height: [Int]) -> Int {
        var left = 0
        var right = height.count - 1
        var maxArea = 0
        
        while left < right {
            let width = right - left
            var tempArea = 0
            
            if height[left] < height[right] {
                tempArea = height[left] * width
                left += 1
            } else {
                tempArea = height[right] * width
                right -= 1
            }
            
            maxArea = max(tempArea, maxArea)
            
        }
        
        return maxArea
    }
    
//  ************ 给你一个链表的头节点 head 和一个整数 val ，请你删除链表中所有满足 Node.val == val 的节点，并返回 新的头节点 。
    
    func removeElements(_ head: ListNode?, _ val: Int) -> ListNode? {
        var dummy: ListNode = ListNode(0)
        dummy.next = head
        var currentNode = dummy
        
        while currentNode.next != nil {
            
            if currentNode.next?.val == val {
                currentNode.next = currentNode.next?.next
            } else {
                currentNode = currentNode.next!
            }
        }
        
        return dummy.next
    }
    
}

let solution = Solution()



